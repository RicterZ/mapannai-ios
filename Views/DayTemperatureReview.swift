#if DEBUG
import SwiftUI

// These are the shipping day-card views, with a fixed local weather fixture for review.
struct DayTemperatureReview: View {
    private var selected: Int {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix("--temperature-case=") }).flatMap { Int($0.split(separator: "=").last ?? "0") } ?? 0
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("每日天气").font(.largeTitle.bold())
                Text("日卡片四种组合 · 示例气温").font(.footnote).foregroundStyle(.secondary)
                ForEach(selected..<(selected + 1)) { index in
                    let photo = index < 2
                    let title = index % 2 == 0
                    let marker = Marker(id: "review", coordinates: Coordinate(latitude: 35, longitude: 139), content: MarkerContent(id: "review", title: "浅草寺", address: "东京", headerImage: photo ? "http://localhost:8766/tokyo.jpg" : nil, iconType: .culture, markdownContent: ""))
                    let day = TripDay(id: "review-\(index)", tripId: "review", date: "2026-10-16", title: title ? "古寺钟声与街巷闲步" : nil, markerIds: [marker.id], chains: [[marker.id]])
                    VStack(alignment: .leading, spacing: 12) {
                        Text((photo ? "有图" : "无图") + " · " + (title ? "有主题" : "无主题")).font(.caption).foregroundStyle(.secondary)
                        JourneyDayCardContent(day: day, index: index, summary: JourneyDaySummary(day: day, index: index, markers: [marker]), loadWeather: false,
                            reviewWeather: TripDayWeather(date: day.date, weatherCode: index % 2 == 0 ? 0 : 61, minimumCelsius: 17, maximumCelsius: 24, precipitationProbability: nil))
                    }
                }
            }.padding(24)
        }.background(Color(uiColor: .systemGroupedBackground)).preferredColorScheme(.light)
    }
}
#endif
