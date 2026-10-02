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
    static func amapNavigationURL(for marker: Marker) -> URL? {
        guard marker.coordinates.isValid else { return nil }
        var url = URLComponents()
        url.scheme = "iosamap"
        url.host = "navi"
        url.queryItems = [
            URLQueryItem(name: "sourceApplication", value: "MapAnNai"),
            URLQueryItem(name: "poiname", value: marker.title),
            URLQueryItem(name: "lat", value: String(marker.coordinates.latitude)),
            URLQueryItem(name: "lon", value: String(marker.coordinates.longitude)),
            URLQueryItem(name: "dev", value: "1"),
            URLQueryItem(name: "style", value: "0")
        ]
        return url.url
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

// Shared by the sheet and the camera command before presentation begins.
struct MarkerDetailLayout {
    let compact: Bool
    let compactHeight: Double
    let restingFraction: Double
    init(marker: Marker, itineraryCount: Int, hasSelectedDay: Bool) {
        let image = URLComponents(string: marker.content.headerImage ?? "")
        let hasImage = (image?.scheme == "https" || image?.scheme == "http") && image?.url != nil
        restingFraction = hasImage ? 0.72 : 0.55
        compact = !NoteContent.hasContent(marker.content.markdownContent) && !hasImage
        compactHeight = min(520, 240 + (marker.content.address?.isEmpty == false ? 40 : 0)
            + Double(itineraryCount) * 52 + (hasSelectedDay ? 48 : 0))
    }
    func occlusion(height: Double, bottomSafeArea: Double) -> Double {
        compact ? compactHeight + bottomSafeArea : height * restingFraction
    }
}
