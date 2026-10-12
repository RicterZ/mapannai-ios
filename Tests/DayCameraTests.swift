import XCTest
@testable import MapAnNai

final class DayCameraTests: XCTestCase {
    @MainActor func testTripSelectionFitsAllValidMembersAndRouteStops() throws {
        let store = AppStore(settings: Settings(), demo: true)
        var trip = try XCTUnwrap(store.trip)
        var first = trip.days[0]
        first.chains = [["missing", store.markers[2].id]]
        first.markerIds = [store.markers[0].id]
        trip.days = [trip.days[1], first]
        store.select(trip: nil, focus: false)
        store.select(trip: trip)
        XCTAssertEqual(store.camera?.points, [0, 2, 3, 4].map { store.markers[$0].coordinates })
        XCTAssertNil(store.camera?.zoomLevel)
        let camera = store.camera?.id
        store.select(trip: nil, focus: false)
        store.select(trip: trip, focus: false)
        XCTAssertEqual(store.camera?.id, camera)
        first.chains = []; first.markerIds = []
        trip.days = [first]
        store.select(trip: trip)
        XCTAssertEqual(store.camera?.id, camera)
    }
    @MainActor func testSelectionKeepsPlannedGeometryButReplanningResetsIt() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        await store.awaitRouteUpdates()
        var route = try XCTUnwrap(store.displayRoutes.first)
        let midpoint = Coordinate(latitude: 31.22, longitude: 121.45)
        route.points = [try XCTUnwrap(route.points.first), midpoint, try XCTUnwrap(route.points.last)]
        route.isPlanned = true
        store.displayRoutes[0] = route
        store.select(trip: trip, focus: false)
        XCTAssertEqual(store.displayRoutes.first { $0.id == route.id }?.points, route.points)
        store.select(trip: trip, day: trip.days[0], focus: false)
        XCTAssertEqual(store.displayRoutes.first { $0.id == route.id }?.points, route.points)
        store.rebuildRoutes()
        await store.awaitRouteUpdates()
        XCTAssertFalse(try XCTUnwrap(store.displayRoutes.first).isPlanned)
    }
    @MainActor func testDayFitsAllValidMembersAndRouteStops() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        var day = trip.days[0]
        day.chains = [[], [store.markers[2].id, store.markers[0].id]]
        day.markerIds = [store.markers[0].id, store.markers[2].id]
        store.select(trip: trip, focus: false)
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.points, [store.markers[0].coordinates, store.markers[2].coordinates])
        XCTAssertNil(store.camera?.zoomLevel)
        XCTAssertNil(store.selectedMarker)
        let points = store.camera?.points
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.points, points)
        let camera = store.camera?.id
        store.select(trip: trip, day: trip.days[1], focus: false)
        XCTAssertEqual(store.camera?.id, camera)
    }
    @MainActor func testDayFitsUnplannedMembersAndEmptyDayKeepsCamera() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        var day = trip.days[0]; day.chains = [[], ["missing"]]
        store.select(trip: trip, focus: false)
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.points, [0, 1, 2].map { store.markers[$0].coordinates })
        let camera = store.camera?.id
        day.id = "empty-day"; day.chains = []; day.markerIds = []
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.id, camera)
    }
    @MainActor func testStartupUsesEarliestDayAndChainOrderRatherThanAllTripBounds() throws {
        let store = AppStore(settings: Settings(), demo: true)
        var trip = try XCTUnwrap(store.trip)
        trip.startDate = "2026-10-01"
        var first = trip.days[0]; first.date = "2026-10-01"
        first.chains = [[], ["missing", store.markers[2].id]]
        first.markerIds = [store.markers[0].id]
        var later = trip.days[1]; later.date = "2026-10-02"
        trip.days = [later, first]
        let marker = StartupCamera.upcomingFirstMarker(trips: [trip], markers: store.markers, today: "2026-09-30")
        XCTAssertEqual(marker?.id, store.markers[2].id)
        first.markerIds = []; first.chains = []
        trip.days = [later, first]
        XCTAssertNil(StartupCamera.upcomingFirstMarker(trips: [trip], markers: store.markers, today: "2026-09-30"))
    }
}
