import SwiftUI
import UIKit

struct JourneyShareGallery: View {
    let photos: [JourneyDayPhoto]
    let images: [URL: UIImage]
    var dayIndex = 0
    var body: some View {
        let available = photos.filter { images[$0.url] != nil }
        VStack(spacing: 16) {
            ForEach(Array(stride(from: 0, to: available.count, by: 2)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(start..<min(start + 2, available.count), id: \.self) { index in
                        let photo = available[index]
                        let size = CGSize(width: available.count == 1 ? 290 : 148, height: available.count == 1 ? 174 : 108)
                        VStack(alignment: .trailing, spacing: 8) {
                            Image(uiImage: Self.feathered(images[photo.url]!, size: size))
                                .resizable().interpolation(.high)
                                .frame(width: size.width + Self.margin * 2, height: size.height + Self.margin * 2)
                                .padding(-Self.margin)
                                .shadow(color: .black.opacity(0.16), radius: 6, y: 3)
                                .rotationEffect(.degrees(available.count == 1 ? (dayIndex.isMultiple(of: 2) ? 2 : -2) : index.isMultiple(of: 2) ? -3 : 3))
                            Text(photo.title).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }.padding(.top, index.isMultiple(of: 2) ? 0 : 10)
                    }
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, available.isEmpty ? 0 : 8)
    }

    static let margin: CGFloat = 2
    /// Rotated clip edges are not antialiased by ImageRenderer; a transparent
    /// border lets bitmap interpolation smooth the rotated photo edges instead.
    static func feathered(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 3; format.opaque = false
        let canvas = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        return UIGraphicsImageRenderer(size: canvas, format: format).image { _ in
            let rect = CGRect(origin: CGPoint(x: margin, y: margin), size: size)
            UIBezierPath(roundedRect: rect, cornerRadius: 8).addClip()
            let scale = max(size.width / max(1, image.size.width), size.height / max(1, image.size.height))
            let drawn = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                                  width: drawn.width, height: drawn.height))
        }
    }
}

struct JourneyShareView: View {
    let trip: Trip
    let markers: [Marker]
    @Environment(\.dismiss) private var dismiss
    @State private var images: [URL: UIImage] = [:]
    @State private var weather: [String: TripDayWeather] = [:]
    @State private var loading = true
    @State private var file: URL?
    @State private var error: String?

    private var days: [TripDay] { trip.days.sorted { ($0.date, $0.id) < ($1.date, $1.id) } }
    private var summaries: [JourneyDaySummary] { JourneyDaySummary.chapters(days: days, markers: markers) }
    private var poster: some View { poster(images: images, weather: weather) }
    private func poster(images: [URL: UIImage], weather: [String: TripDayWeather]) -> some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(trip.name).font(.largeTitle.bold())
                Text("\(days.first?.date ?? "") — \(days.last?.date ?? "") · \(days.count)天")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
            let chapters = summaries
            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                JourneyDayCardContent(day: day, index: index, summary: chapters[index], loadPhotos: false,
                    loadWeather: false, sharing: true, sharePhotos: images, shareWeather: weather[day.id])
            }
            Text("MapAnNai · 我的旅途").font(.caption2).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity).padding(.top, 4)
        }
        .padding(24).frame(width: 390)
        .background(Color(uiColor: .systemGroupedBackground))
        .environment(\.colorScheme, .light)
        .environment(\.dynamicTypeSize, .large)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if loading { ProgressView("正在准备照片…").padding(32) }
                poster
                if let error { Text(error).font(.footnote).foregroundStyle(.secondary).padding() }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("分享旅途").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    if let file { ShareLink(item: file) { Image(systemName: "square.and.arrow.up") }.accessibilityLabel("分享长图") }
                    else { ProgressView() }
                }
            }
            .task { await prepare() }
        }
    }

    @MainActor private func prepare() async {
        let photos = summaries.flatMap(\.photos)
        var images: [URL: UIImage] = [:]
        var weather: [String: TripDayWeather] = [:]
        for photo in photos {
            guard !Task.isCancelled else { return }
            if let image = await JourneyPhotoCache.shared.image(for: photo.url) { images[photo.url] = image }
        }
        for day in days {
            let points = TripWeatherLocation.points(day: day, trip: trip, markers: markers)
            if let coordinate = await TripWeatherLocationCache.shared.representative(points),
               let cached = await TripWeatherService.shared.cachedWeather(for: day.date, at: coordinate) {
                weather[day.id] = cached
            }
        }
        guard !Task.isCancelled else { return }
        self.images = images; self.weather = weather
        loading = false
        if images.count < Set(photos.map(\.url)).count { error = "部分照片未能载入，长图仅包含已载入的照片。" }
        // State writes are not readable here until the next view update; render from the local snapshot.
        let snapshot = poster(images: images, weather: weather)
        let renderer = ImageRenderer(content: snapshot)
        renderer.scale = 2
        let measure = ImageRenderer(content: snapshot.fixedSize(horizontal: false, vertical: true))
        measure.scale = 1
        if let size = measure.uiImage?.size { renderer.scale = min(2, 16000 / max(1, size.height)) }
        guard let image = renderer.uiImage else { error = "无法生成长图，请稍后重试。"; return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TripShares", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("png")
            let data = await Task.detached(priority: .userInitiated) { image.pngData() }.value
            guard let data else { error = "无法生成长图，请稍后重试。"; return }
            try await Task.detached(priority: .userInitiated) { try data.write(to: url, options: .atomic) }.value
            file = url
        } catch { self.error = "长图保存失败，请稍后重试。" }
    }
}
