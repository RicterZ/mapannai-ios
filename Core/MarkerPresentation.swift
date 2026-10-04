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
    static func googleNavigationURL(for marker: Marker) -> URL? {
        guard marker.coordinates.isValid else { return nil }
        var url = URLComponents(string: "https://www.google.com/maps/dir/")!
        url.queryItems = [URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(marker.coordinates.latitude),\(marker.coordinates.longitude)"),
            URLQueryItem(name: "dir_action", value: "navigate")]
        if let reference = marker.placeReferences?.google {
            url.queryItems?.append(URLQueryItem(name: "destination_place_id", value: reference.placeId))
        }
        return url.url
    }
    @MainActor static func openAppleMaps(for marker: Marker, selectedItem: MKMapItem? = nil) async {
        if let selectedItem { selectedItem.openInMaps(launchOptions: nil); return }
        if #available(iOS 18.0, *), let value = marker.placeReferences?.apple?.placeId,
           let identifier = MKMapItem.Identifier(rawValue: value),
           let item = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem {
            item.openInMaps(launchOptions: nil)
            return
        }
        appleMapsItem(for: marker)?.openInMaps(launchOptions: nil)
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
