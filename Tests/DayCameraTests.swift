import XCTest
@testable import MapAnNai

final class DayCameraTests: XCTestCase {
    @MainActor func testTripSelectionUsesFirstValidStopAtZoom12() throws {
        let store = AppStore(settings: Settings(), demo: true)
        var trip = try XCTUnwrap(store.trip)
        var first = trip.days[0]
        first.chains = [["missing", store.markers[2].id]]
        first.markerIds = [store.markers[0].id]
        trip.days = [trip.days[1], first]
        store.select(trip: nil, focus: false)
        store.select(trip: trip)
        XCTAssertEqual(store.camera?.points, [store.markers[2].coordinates])
        XCTAssertEqual(store.camera?.zoomLevel, 12)
        let camera = store.camera?.id
        store.select(trip: nil, focus: false)
        store.select(trip: trip, focus: false)
        XCTAssertEqual(store.camera?.id, camera)
        first.chains = []; first.markerIds = []
        trip.days = [first, trip.days[0]]
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
    @MainActor func testDayUsesFirstNonemptyChainAndAbsoluteZoom() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        var day = trip.days[0]
        day.chains = [[], [store.markers[2].id, store.markers[0].id]]
        day.markerIds = [store.markers[0].id, store.markers[2].id]
        store.select(trip: trip, focus: false)
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.points, [store.markers[2].coordinates])
        XCTAssertEqual(store.camera?.zoomLevel, 15)
        XCTAssertNil(store.selectedMarker)
        let camera = store.camera?.id
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.id, camera)
        store.select(trip: trip, day: trip.days[1], focus: false)
        XCTAssertEqual(store.camera?.id, camera)
    }
    @MainActor func testMissingRoutePointNeverFitsWholeDayOrUsesMemberOrder() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        store.focus(store.markers[0]); let camera = store.camera?.id
        var day = trip.days[0]; day.chains = [[], ["missing"]]
        store.select(trip: trip, focus: false)
        store.select(trip: trip, day: day)
        XCTAssertEqual(store.camera?.id, camera)
        day.id = "no-route"; day.chains = []
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
