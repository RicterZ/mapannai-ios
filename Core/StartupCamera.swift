import Foundation

// Dates from the server are local calendar dates, not UTC timestamps.
enum StartupCamera {
    static func localDate(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    static func upcomingMarkers(trips: [Trip], markers: [Marker], today: String) -> [Marker] {
        let upcoming = trips.filter { $0.startDate >= today }.sorted {
            $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate
        }
        for trip in upcoming {
            let ids = Set(trip.days.filter { $0.tripId == trip.id }.flatMap(\.markerIds))
            let places = markers.filter { ids.contains($0.id) && $0.coordinates.isValid }
            if !places.isEmpty { return places }
        }
        return []
    }
}
