import Foundation
import MapKit

struct MarkerItinerary: Identifiable {
    let trip: Trip
    let day: TripDay
    let dayNumber: Int
    var id: String { trip.id + "/" + day.id }
}
enum MarkerPresentation {
    static func itineraries(for markerID: String, trips: [Trip]) -> [MarkerItinerary] {
        trips.flatMap { trip in
            trip.days.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
                .enumerated().compactMap { index, day in
                    guard day.tripId == trip.id, day.markerIds.contains(markerID) else { return nil }
                    return MarkerItinerary(trip: trip, day: day, dayNumber: index + 1)
                }
        }
    }
    static func appleMapsItem(for marker: Marker) -> MKMapItem? {
        guard marker.coordinates.isValid else { return nil }
        // Match the Web popup's Apple Maps boundary conversion; stored coordinates stay WGS-84.
        let point = Coordinates.gcj(marker.coordinates)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)))
        item.name = marker.title
        return item
    }
}
