import SwiftUI
import ImageIO

/// Read-only presentation: routes provide order; membership alone does not.
struct JourneyDaySummary {
    let theme: String?
    let places: String
    let timing: String?
    let transport: String?
    let count: Int
    let coverURL: URL?

    init(day: TripDay, index: Int, markers: [Marker]) {
        let lookup = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let title = day.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        theme = title.isEmpty || title.replacingOccurrences(of: " ", with: "") == "第\(index + 1)天" || title == day.date ? nil : title
        count = Set(day.markerIds + day.chains.flatMap { $0 }).intersection(Set(lookup.keys)).count
        let routes = day.chains.filter { !$0.isEmpty }
        let routed = Set(routes.flatMap { $0 })
        let extra = day.markerIds.filter { !routed.contains($0) && lookup[$0] != nil }
        if routes.isEmpty {
            places = day.markerIds.compactMap { lookup[$0]?.title }.joined(separator: " · ")
        } else {
            var lines = routes.map { $0.compactMap { lookup[$0]?.title }.joined(separator: " → ") }.filter { !$0.isEmpty }
            if !extra.isEmpty { lines.append("另有\(extra.count)个地点") }
            places = lines.joined(separator: "\n")
        }
        let schedules = day.chains.indices.compactMap { day.scheduledRoute(at: $0) }
        let firstRouteIndex = day.chains.firstIndex { !$0.isEmpty }
        if let firstRouteIndex, let time = day.scheduledRoute(at: firstRouteIndex)?.stops.first?.startTime, !time.isEmpty {
            timing = time + " 首站"
        } else {
            let visits = schedules.flatMap(\.stops).filter { $0.startTime?.isEmpty == false || ($0.durationMinutes ?? 0) > 0 }.count
            let legs = schedules.flatMap { route in route.stops.indices.dropLast().compactMap { route.leg(at: $0) } }
            let transfers = legs.filter { $0.startTime?.isEmpty == false || ($0.durationMinutes ?? 0) > 0 }.count
            timing = "\(visits + transfers)项时间安排"
        }
        var modes: [TransportMode] = []
        for route in schedules {
            for position in route.stops.indices.dropLast() {
                if let mode = route.leg(at: position)?.mode, !modes.contains(mode) { modes.append(mode) }
            }
        }
        transport = modes.isEmpty ? nil : modes.prefix(2).map(\.label).joined(separator: "·") + (modes.count > 2 ? "等\(modes.count)种交通" : "")
        coverURL = Self.cover(ids: routes.flatMap { $0 } + day.markerIds, markers: lookup)
    }

    static func cover(trip: Trip, markers: [Marker]) -> URL? {
        let ids = trip.days.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            .flatMap { $0.chains.flatMap { $0 } + $0.markerIds } + (trip.markerIds ?? [])
        return cover(ids: ids, markers: Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }))
    }
    private static func cover(ids: [String], markers: [String: Marker]) -> URL? {
        ids.lazy.compactMap { markers[$0]?.content.headerImage.flatMap(imageURL) }.first
    }
}

// Decode off the main actor; share the same pixels with the archive's ImageRenderer.
actor JourneyPhotoCache {
    static let shared = JourneyPhotoCache()
    private let cache = NSCache<NSURL, UIImage>()
    private var requests: [URL: Task<UIImage?, Never>] = [:]
    init() { cache.totalCostLimit = 32 * 1024 * 1024 }
    func image(for url: URL) async -> UIImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        if let request = requests[url] { return await request.value }
        let request = Task { () -> UIImage? in
            do {
                let (data, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 20))
                guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode),
                      let source = CGImageSourceCreateWithData(data as CFData, nil),
                      let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: 1000,
                        kCGImageSourceShouldCacheImmediately: true
                      ] as CFDictionary) else { return nil }
                return UIImage(cgImage: thumbnail)
            } catch { return nil }
        }
        requests[url] = request
        let image = await request.value
        requests[url] = nil
        if let image { cache.setObject(image, forKey: url as NSURL, cost: (image.cgImage?.bytesPerRow ?? 0) * (image.cgImage?.height ?? 0)) }
        return image
    }
}

struct JourneyDayCardContent: View {
    let day: TripDay
    let index: Int
    let markers: [Marker]
    var loadPhotos = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photo: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        let summary = JourneyDaySummary(day: day, index: index, markers: markers)
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { dayTitle; Spacer(minLength: 12); date }
                VStack(alignment: .leading, spacing: 5) { dayTitle; date }
            }
            if summary.count == 0 {
                Text("还没有安排地点").font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 7) {
                        if let theme = summary.theme {
                            Text(theme).font(.headline).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                        if summary.theme == nil {
                            untitledPlaces
                        } else if !summary.places.isEmpty {
                            Text(summary.places)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if let photo, loadedURL == summary.coverURL, !typeSize.isAccessibilitySize {
                        Image(uiImage: photo).resizable().scaledToFill().frame(width: summary.theme == nil ? 60 : 72, height: summary.theme == nil ? 60 : 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                    }
                }
                .frame(minHeight: summary.coverURL != nil && !typeSize.isAccessibilitySize ? (summary.theme == nil ? 60 : 76) : nil, alignment: .top)
            }
            Rectangle().fill(.quaternary).frame(height: 0.5).accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { timing(summary); Spacer(minLength: 4); transport(summary); count(summary) }
                VStack(alignment: .leading, spacing: 6) {
                    HStack { timing(summary); Spacer(minLength: 4); count(summary) }
                    transport(summary)
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .foregroundStyle(.primary).padding(.top, 12)
        .task(id: loadPhotos ? summary.coverURL : nil) {
            guard loadPhotos, let url = summary.coverURL else { return }
            let image = await JourneyPhotoCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { photo = image; loadedURL = url }
        }
    }
    private var untitledPlaces: some View {
        let route = day.chains.first { !$0.isEmpty }
        let ids = route ?? day.markerIds
        return ViewThatFits(in: .horizontal) {
            placePreview(ids: ids, limit: 3, ordered: route != nil, wholeNames: true)
            placePreview(ids: ids, limit: 2, ordered: route != nil, wholeNames: true)
            placePreview(ids: ids, limit: 1, ordered: route != nil, wholeNames: false)
        }
    }
    private func placePreview(ids: [String], limit: Int, ordered: Bool, wholeNames: Bool) -> some View {
        let shown = Array(ids.prefix(limit))
        let remaining = Set(day.markerIds).subtracting(shown).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(Array(shown.enumerated()), id: \.offset) { position, id in
                    if position > 0 {
                        if ordered { Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary) }
                        else { Text("·").foregroundStyle(.tertiary) }
                    }
                    Text(markers.first { $0.id == id }?.title ?? "未载入地点")
                        .lineLimit(1).fixedSize(horizontal: wholeNames, vertical: false)
                }
            }.font(.subheadline).foregroundStyle(Color(uiColor: .label).opacity(0.8))
            if remaining > 0 {
                Text("另有 \(remaining) 个地点").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var dayTitle: some View { Text("第\(index + 1)天").font(.headline) }
    private var date: some View {
        Text(Self.dateFormatter.string(from: Date.fromDay(day.date)))
            .font(.caption).foregroundStyle(.secondary).fixedSize()
    }
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd·EEE"
        return formatter
    }()
    @ViewBuilder private func timing(_ summary: JourneyDaySummary) -> some View {
        if let timing = summary.timing {
            HStack(spacing: 4) {
                Image(systemName: "clock").accessibilityHidden(true)
                Text(timing)
            }.fixedSize(horizontal: true, vertical: false)
        }
    }
    @ViewBuilder private func transport(_ summary: JourneyDaySummary) -> some View {
        if let transport = summary.transport { Text(transport).fixedSize(horizontal: true, vertical: false) }
    }
    private func count(_ summary: JourneyDaySummary) -> some View { Text("\(summary.count) 个地点").fixedSize() }
}
