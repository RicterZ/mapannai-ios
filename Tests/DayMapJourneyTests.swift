import XCTest
@testable import MapAnNai

final class DayMapJourneyTests: XCTestCase {
    private let markers = (0..<4).map { index in
        Marker(id: "p\(index)", coordinates: Coordinate(latitude: 31.2 + Double(index) * 0.01, longitude: 121.4),
            content: MarkerContent(id: "p\(index)", title: "地点\(index)", markdownContent: ""))
    }
    @MainActor func testSearchRestoresAllSavedMarkersAndExitRestoresDayScope() {
        let store = AppStore(settings: Settings(), demo: true)
        store.markers = markers
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-12", markerIds: ["p0"], chains: [["p0"]])
        store.trips = [Trip(id: "t", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        store.select(trip: store.trips.first, day: day, focus: false)
        store.beginDayMapBrowsing()
        XCTAssertEqual(store.mapMarkers.map(\.id), ["p0"])
        store.beginAddingPlace(to: day)
        XCTAssertEqual(store.mapMarkers.map(\.id), markers.map(\.id))
        store.endAddingPlace()
        XCTAssertEqual(store.mapMarkers.map(\.id), ["p0"])
    }
    @MainActor func testMapTapOpensDayPlaceDetailWithoutChangingDayScope() {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = store.trips[0], day = store.trips[0].days[0]
        store.select(trip: trip, day: day, focus: false)
        store.beginDayMapBrowsing()
        let marker = store.mapMarkers[0]
        store.selectMapMarker(marker)
        XCTAssertEqual(store.selectedMarker?.id, marker.id)
        XCTAssertEqual(store.dayMapFocusID, marker.id)
        XCTAssertEqual(store.dayID, day.id)
        store.selectedMarker = nil
        store.focusDayMapMarker(store.mapMarkers[1].id)
        XCTAssertNil(store.selectedMarker)
    }
    func testPlaceCategorySkipsGenericProviderTypes() {
        var place = Place(id: "test", name: "Hotel", address: "", coordinates: Coordinate(latitude: 35, longitude: 140), types: ["point_of_interest", "lodging", "establishment"])
        XCTAssertEqual(place.categoryLabel, "住宿")
        place.types = ["point_of_interest", "establishment"]
        XCTAssertNil(place.categoryLabel)
        place.types = ["旅游景点", "point_of_interest"]
        XCTAssertEqual(place.categoryLabel, "旅游景点")
    }
    func testSeparateRoutesAndUnplannedPlacesHaveNoInventedConnections() {
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-12", markerIds: ["p3", "p2", "p0", "p1"], chains: [["p0", "p1"], ["p2"]])
        let stops = DayMapJourney.stops(day: day, markers: markers)
        XCTAssertEqual(stops.map(\.marker.id), ["p0", "p1", "p2", "p3"])
        let route = DisplayRoute(id: "d|0|1|p0|p1", dayID: "d", tripID: "t", colorIndex: 0, points: [], isPlanned: true, distance: 850)
        XCTAssertEqual(DayMapJourney.distance(after: stops[0], next: stops[1], day: day, routes: [route]), "850 m")
        XCTAssertNil(DayMapJourney.distance(after: stops[1], next: stops[2], day: day, routes: [route]))
        var fallback = route; fallback.isDashed = true
        XCTAssertEqual(DayMapJourney.distance(after: stops[0], next: stops[1], day: day, routes: [fallback]), "直线 1.1 km")
        XCTAssertEqual(DayMapJourney.distance(after: stops[0], next: stops[1], day: day, routes: []), "直线 1.1 km")
        var invalid = stops[1].marker; invalid.coordinates.latitude = .nan
        let invalidStop = DayMapStop(id: "invalid", marker: invalid, routeIndex: 0, position: 1, visit: nil, leg: nil)
        XCTAssertNil(DayMapJourney.distance(after: stops[0], next: invalidStop, day: day, routes: []))
    }
    func testStaleMembershipDoesNotCreateFourthPlaceOrEmptyGroup() {
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-01",
            markerIds: ["deleted", "p0", "p1", "p2"], chains: [["p0", "p1", "p2"]])
        let summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertEqual(summary.count, 3)
        XCTAssertFalse(summary.places.contains("另有"))
        XCTAssertEqual(DayMapJourney.stops(day: day, markers: markers).map(\.marker.id), ["p0", "p1", "p2"])
        XCTAssertEqual(day.markerIds.count, 4, "Display must not mutate server membership")
    }
    func testMissingMemberDetailIsFetchedEvenAfterFreshList() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://missing-member.invalid", token: "test-only", session: URLSession(configuration: config))
        let marker = markers[0]
        let payload = try JSONEncoder().encode(marker)
        MockURLProtocol.handler = { request in
            switch request.url!.lastPathComponent {
            case "markers", "trips": return (200, Data("[]".utf8))
            case marker.id: return (200, payload)
            default: XCTFail("Unexpected request"); return (404, Data())
            }
        }
        defer { MockURLProtocol.handler = nil }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = MarkerRepository(directory: directory)
        _ = try await repository.refresh(using: client)
        let restored = try await repository.detail(marker.id, using: client)
        XCTAssertEqual(restored, marker)
        let cached = await repository.cached(using: client)
        XCTAssertEqual(cached?.markers, [marker])
    }
    @MainActor func testManualMapInteractionStopsCameraFollowingWithoutStoppingFocus() {
        let settings = Settings(); let store = AppStore(settings: settings, demo: true)
        store.markers = markers
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-12", markerIds: ["p0", "p1"], chains: [["p0", "p1"]])
        store.trips = [Trip(id: "t", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        store.select(trip: store.trips.first, day: day, focus: false)
        store.beginDayMapBrowsing()
        XCTAssertEqual(store.mapMarkers.map(\.id), ["p0", "p1"])
        XCTAssertEqual(store.dayMapFocusID, "p0"); XCTAssertNil(store.selectedMarker)
        store.focusDayMapMarker("p1")
        XCTAssertEqual(store.camera?.points, [markers[1].coordinates])
        store.noteMapInteraction()
        let cameraID = store.camera?.id
        store.focusDayMapMarker("p0")
        XCTAssertEqual(store.dayMapFocusID, "p0")
        XCTAssertEqual(store.camera?.id, cameraID)
        store.focus(markers[1])
        XCTAssertEqual(store.dayMapFocusID, "p1"); XCTAssertNil(store.selectedMarker)
        XCTAssertEqual(store.camera?.id, cameraID)
        store.showWholeDayOnMap()
        XCTAssertTrue(store.dayMapCameraFollowing)
        XCTAssertEqual(Set(store.camera?.points ?? []), Set(markers.prefix(2).map(\.coordinates)))
        store.noteDayMapTransform()
        XCTAssertFalse(store.dayMapCameraFollowing)
        store.endDayMapBrowsing()
        XCTAssertNil(store.dayMapFocusID)
        XCTAssertEqual(store.mapMarkers.count, 4)
    }
}
