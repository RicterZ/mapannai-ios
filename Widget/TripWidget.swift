import WidgetKit
import SwiftUI

struct TripWidgetSnapshot: Codable { var tripName: String; var date: String; var theme: String?; var places: [String]; var weather: String? }
struct TripProvider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, snapshot: .init(tripName: "我的旅途", date: "今天", theme: "等待同步今日行程", places: [], weather: nil)) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(load()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) { let entry = load(); completion(Timeline(entries: [entry], policy: .after(Calendar.current.date(byAdding: .hour, value: 1, to: .now)!))) }
    private func load() -> Entry {
        let defaults = UserDefaults(suiteName: "group.me.mapannai.ios")
        let snapshot = (try? JSONDecoder().decode(TripWidgetSnapshot.self, from: defaults?.data(forKey: "today-widget") ?? Data())) ?? .init(tripName: "我的旅途", date: "今天", theme: nil, places: [], weather: nil)
        return Entry(date: .now, snapshot: snapshot)
    }
    struct Entry: TimelineEntry { let date: Date; let snapshot: TripWidgetSnapshot }
}
struct TripWidgetView: View {
    let entry: TripProvider.Entry
    @Environment(\.widgetFamily) private var family
    var body: some View { VStack(alignment: .leading, spacing: 8) {
        HStack { Text(entry.snapshot.tripName).font(.headline).lineLimit(1); Spacer(); if let weather = entry.snapshot.weather { Text(weather) } }
        Text(entry.snapshot.date).font(.caption).foregroundStyle(.secondary)
        if let theme = entry.snapshot.theme { Text(theme).font(.title3.weight(.semibold)).lineLimit(2) }
        if entry.snapshot.places.isEmpty {
            Text("行程尚未同步").font(.subheadline).foregroundStyle(.secondary)
            Text("打开 App 查看今日安排").font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Array(entry.snapshot.places.prefix(family == .systemLarge ? 8 : 3).enumerated()), id: \.offset) { index, place in
            HStack(spacing: 8) { Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 18); Text(place).font(.subheadline).lineLimit(1) }
        }
        if family == .systemLarge { Spacer(); Text("打开查看全部").font(.caption).foregroundStyle(.secondary) }
    }.padding().containerBackground(.background, for: .widget) }
}
@main struct TripWidgetBundle: Widget { var body: some WidgetConfiguration { StaticConfiguration(kind: "TripWidget", provider: TripProvider()) { TripWidgetView(entry: $0) }.configurationDisplayName("今日行程").description("查看今天的旅途安排").supportedFamilies([.systemMedium, .systemLarge]) } }
