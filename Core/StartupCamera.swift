import Foundation

// Dates from the server are local calendar dates, not UTC timestamps.
enum StartupCamera {
    static func localDate(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
    static func upcomingFirstMarker(trips: [Trip], markers: [Marker], today: String) -> Marker? {
        let upcoming = trips.filter { $0.startDate >= today }.sorted {
            $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate
        }
        for trip in upcoming {
            guard let firstDay = trip.days.filter({ $0.tripId == trip.id }).sorted(by: {
                $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
            }).first else { continue }
            for id in firstDay.chains.flatMap({ $0 }) + firstDay.markerIds {
                if let marker = markers.first(where: { $0.id == id && $0.coordinates.isValid }) { return marker }
            }
        }
        return nil
    }
}
