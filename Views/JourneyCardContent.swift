import SwiftUI
import ImageIO

/// Read-only presentation: routes provide order; membership alone does not.
struct JourneyDaySummary {
    let theme: String?
    let places: String
    let routePreviews: [[String]]
    let unplannedPlaces: [String]
    let timing: String?
    let transport: String?
    let count: Int
    let coverURL: URL?
    let coverTitle: String?

    init(day: TripDay, index: Int, markers: [Marker], excludingPhotos: Set<URL> = []) {
        let lookup = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let title = day.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        theme = title.isEmpty || title.replacingOccurrences(of: " ", with: "") == "第\(index + 1)天" || title == day.date ? nil : title
        count = Set(day.markerIds + day.chains.flatMap { $0 }).intersection(Set(lookup.keys)).count
        let routes = day.chains.filter { !$0.isEmpty }
        let routed = Set(routes.flatMap { $0 })
        let extra = day.markerIds.filter { !routed.contains($0) && lookup[$0] != nil }
        routePreviews = routes.map { $0.compactMap { lookup[$0]?.title } }.filter { !$0.isEmpty }
        unplannedPlaces = extra.compactMap { lookup[$0]?.title }
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
        let coverMarker = (routes.flatMap { $0 } + day.markerIds).lazy.compactMap { lookup[$0] }
            .first { marker in
                guard let url = marker.content.headerImage.flatMap(imageURL) else { return false }
                return !excludingPhotos.contains(url)
            }
        coverURL = coverMarker?.content.headerImage.flatMap(imageURL)
        coverTitle = coverMarker?.title
    }

    // Assign in display order, not image-load or scroll order.
    static func chapters(days: [TripDay], markers: [Marker], excludingPhotos: Set<URL> = []) -> [JourneyDaySummary] {
        var used = excludingPhotos
        return days.enumerated().map { index, day in
            let summary = JourneyDaySummary(day: day, index: index, markers: markers, excludingPhotos: used)
            if let url = summary.coverURL { used.insert(url) }
            return summary
        }
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
    private static let imageCache = NSCache<NSURL, UIImage>()
    nonisolated static func cachedImage(for url: URL) -> UIImage? { imageCache.object(forKey: url as NSURL) }
    private let cache = JourneyPhotoCache.imageCache
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
    let summary: JourneyDaySummary
    var loadPhotos = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var photo: UIImage?
    @State private var loadedURL: URL?

    var body: some View {
        let cachedPhoto = summary.coverURL.flatMap(JourneyPhotoCache.cachedImage(for:))
        let displayPhoto = photo ?? cachedPhoto
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) { dayTitle; dateRule; date }
                    VStack(alignment: .leading, spacing: 6) { dayTitle; date }
                }
                Spacer(minLength: 8)
                Color.clear.frame(width: 44, height: 34).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 16) {
            if let theme = summary.theme {
                Text(theme).font(.title2.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if summary.coverURL != nil {
                VStack(alignment: .trailing, spacing: 6) {
                    Color.clear.aspectRatio(2.2, contentMode: .fit)
                        .overlay {
                            if let photo = displayPhoto, loadedURL == summary.coverURL || cachedPhoto != nil {
                                GeometryReader { geometry in
                                    Image(uiImage: photo).resizable().scaledToFill()
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped()
                                }
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityHidden(true)
                    Text(summary.coverTitle ?? "").font(.caption2).foregroundStyle(.secondary)
                        .opacity(displayPhoto != nil && (loadedURL == summary.coverURL || cachedPhoto != nil) ? 1 : 0)
                }
            }
            if summary.count == 0 {
                Text("还没有安排地点").font(.subheadline).foregroundStyle(.secondary)
            } else {
                JourneyRoutePreview(summary: summary)
            }
            Text("\(summary.count) 个地点" + (summary.timing.map { " · " + $0 } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 16))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
        .task(id: loadPhotos ? summary.coverURL : nil) {
            guard loadPhotos, let url = summary.coverURL else { return }
            let image = await JourneyPhotoCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { photo = image; loadedURL = url }
        }
    }
    private var dayTitle: some View {
        Text(String(format: "%02d", index + 1))
            .font(.largeTitle.weight(.regular)).monospacedDigit()
            .accessibilityLabel("第\(index + 1)天")
    }
    private var dateRule: some View {
        Rectangle().fill(.tertiary).frame(width: 20, height: 0.5).accessibilityHidden(true)
    }
    private var date: some View {
        Text(Self.chapterDateFormatter.string(from: Date.fromDay(day.date)))
            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
    private static let chapterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "M月d日 · EEE"
        return formatter
    }()
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MM/dd·EEE"
        return formatter
    }()
}

/// A preview, not a second full itinerary: keep separate routes and unordered members distinct.
private struct JourneyRoutePreview: View {
    let summary: JourneyDaySummary
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(summary.routePreviews.prefix(2).enumerated()), id: \.offset) { routeIndex, names in
                VStack(alignment: .leading, spacing: 0) {
                    if summary.routePreviews.count > 1 {
                        Text("路线 \(routeIndex + 1)").font(.caption).foregroundStyle(.secondary).padding(.bottom, 8)
                    }
                    let shown = Array(names.prefix(3))
                    ForEach(Array(shown.enumerated()), id: \.offset) { index, name in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Circle().strokeBorder(Color(uiColor: .secondaryLabel), lineWidth: 1)
                                    .frame(width: 6, height: 6).padding(.top, 7)
                                Rectangle().fill(Color(uiColor: .separator)).frame(width: 1)
                                    .opacity(index < shown.count - 1 || names.count > shown.count ? 1 : 0)
                            }.frame(width: 10).accessibilityHidden(true)
                            Text(name).font(.subheadline).foregroundStyle(.primary)
                                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, index < shown.count - 1 || names.count > shown.count ? 12 : 0)
                        }.fixedSize(horizontal: false, vertical: true)
                    }
                    if names.count > shown.count {
                        Text("还有 \(names.count - shown.count) 站")
                            .font(.caption).foregroundStyle(.secondary).padding(.leading, 22)
                    }
                }
            }
            if summary.routePreviews.count > 2 {
                Text("还有 \(summary.routePreviews.count - 2) 条路线").font(.caption).foregroundStyle(.secondary)
            }
            if !summary.unplannedPlaces.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("未编排 · \(summary.unplannedPlaces.count) 个地点")
                        .font(.caption).foregroundStyle(.secondary)
                    if summary.routePreviews.isEmpty {
                        Text(summary.unplannedPlaces.joined(separator: " · "))
                            .font(.subheadline).foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                    }
                }.padding(.top, summary.routePreviews.isEmpty ? 0 : 2)
            }
        }
    }
}
