import Foundation
import WidgetKit

struct SharedTripWidgetSnapshot: Codable {
    var tripName: String
    var date: String
    var theme: String?
    var places: [String]
    var weather: String?
}

enum WidgetSnapshotWriter {
    static let suite = "group.me.mapannai.ios"
    static func write(trips: [Trip], markers: [Marker], now: Date = .now) {
        let calendar = Calendar.current
        let today = now.dayString
        let candidates = trips.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        guard let trip = candidates.first(where: { $0.days.contains(where: { $0.date == today }) }), let day = trip.days.first(where: { $0.date == today }) else {
            save(.init(tripName: "我的旅途", date: today, theme: nil, places: [], weather: nil)); return
        }
        let ids = Set(day.markerIds + day.chains.flatMap { $0 })
        let names = markers.filter { ids.contains($0.id) }.map { $0.title }
        save(.init(tripName: trip.name, date: today, theme: day.title, places: names, weather: nil))
    }
    private static func save(_ snapshot: SharedTripWidgetSnapshot) {
        guard let defaults = UserDefaults(suiteName: suite), let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "today-widget")
        WidgetCenter.shared.reloadTimelines(ofKind: "TripWidget")
    }
}
