import XCTest
@testable import MapAnNai

final class RouteSelectionTests: XCTestCase {
    private func route(_ id: String, day: String = "day", offset: Double = 0) -> DisplayRoute {
        DisplayRoute(id: id, dayID: day, tripID: "trip", colorIndex: 0,
            points: [Coordinate(latitude: offset, longitude: 0), Coordinate(latitude: offset, longitude: 100)], isPlanned: false)
    }
    func testHitUsesSamePathAndDeduplicatesDates() {
        let routes = [route("a"), route("b"), route("c", day: "other", offset: 1)]
        let candidates = RouteSelection.candidates(at: (50, 0), routes: routes) { ($0.longitude, $0.latitude) }
        XCTAssertEqual(Set(candidates.map(\.dayID)), ["day", "other"])
        XCTAssertTrue(RouteSelection.candidates(at: (50, 19), routes: [routes[0]]) { ($0.longitude, $0.latitude) }.isEmpty)
    }
    func testMovingCircleUsesPathDistanceAndLoopsContinuously() throws {
        let points = [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1),
                      Coordinate(latitude: 0, longitude: 3)]
        let path = RouteMotionPath(points: points)
        XCTAssertEqual(path.position(progress: 0), points.first)
        XCTAssertEqual(path.position(progress: 1), points.last)
        XCTAssertEqual(try XCTUnwrap(path.position(progress: 0.5)).longitude, 1.5, accuracy: 0.001)
        XCTAssertEqual(RouteMotionPath.phase(elapsed: 1.2), 0.5, accuracy: 0.001)
        XCTAssertEqual(RouteMotionPath.phase(elapsed: 3.6), 0.5, accuracy: 0.001)
        XCTAssertEqual(RouteMotionPath.phase(elapsed: 24), 0, accuracy: 0.001)
        let routes = [route("day|0|1"), route("day|1|1")]
        XCTAssertEqual(RouteSelection.paths(routes).count, 2, "Separate chains must not animate across an invented link")
    }
    @MainActor func testRouteClickSelectsDayPreservesCameraAndCanBeRepeated() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        await store.awaitRouteUpdates()
        let route = try XCTUnwrap(store.displayRoutes.first)
        let trip = try XCTUnwrap(store.trip)
        store.select(trip: trip, focus: false); await store.awaitRouteUpdates()
        let camera = store.camera?.id, first = store.routeSelectionRequest
        store.selectRoute(route)
        XCTAssertEqual(store.dayID, route.dayID)
        XCTAssertEqual(store.camera?.id, camera)
        XCTAssertNotEqual(store.routeSelectionRequest, first)
        let second = store.routeSelectionRequest
        store.selectRoute(route)
        XCTAssertNotEqual(store.routeSelectionRequest, second)
        XCTAssertEqual(store.camera?.id, camera)
    }
    @MainActor func testDayChoicesUseChronologicalNumbersAndKeepTapAnchor() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        await store.awaitRouteUpdates()
        store.select(trip: try XCTUnwrap(store.trip), focus: false)
        await store.awaitRouteUpdates()
        let first = try XCTUnwrap(store.displayRoutes.first { $0.dayID == "day-1" })
        let second = try XCTUnwrap(store.displayRoutes.first { $0.dayID == "day-2" })
        store.trips[0].days.reverse()
        XCTAssertEqual(store.routeDayLabel(first), "第1天")
        XCTAssertEqual(store.routeDayLabel(second), "第2天")
        store.offerRoutes([second, first], at: CGPoint(x: 80, y: 120))
        XCTAssertEqual(store.routeCandidatePoint, CGPoint(x: 80, y: 120))
        XCTAssertEqual(store.routeCandidates.map(\.dayID), ["day-1", "day-2"])
        store.selectRoute(second)
        XCTAssertTrue(store.routeCandidates.isEmpty)
    }

}
