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
    func testMovingCircleMaintainsScreenSpeedAcrossZoomAndFrameRates() throws {
        let path = RouteMotionPath(points: [Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 0, longitude: 20), Coordinate(latitude: 0, longitude: 500)])
        let animation = RouteMotionAnimation(); animation.reset(paths: [path])
        var scale = 1.0
        let project: (Coordinate) -> CGPoint = { CGPoint(x: $0.longitude * scale, y: 0) }
        _ = animation.positions(timestamp: 0, project: project)
        var position = CGPoint.zero
        for frame in 1...60 {
            position = try XCTUnwrap(animation.positions(timestamp: Double(frame) / 60, project: project).first ?? nil)
        }
        XCTAssertEqual(position.x, 60, accuracy: 0.001)
        // Zoom retains the same segment/fraction; only the next frame's travel is added.
        scale = 2
        position = try XCTUnwrap(animation.positions(timestamp: 1 + 1.0 / 60, project: project).first ?? nil)
        XCTAssertEqual(position.x, 121, accuracy: 0.001)
        scale = 0.5
        position = try XCTUnwrap(animation.positions(timestamp: 1 + 2.0 / 60, project: project).first ?? nil)
        XCTAssertEqual(position.x, 31.25, accuracy: 0.001)
        for frame in 1...120 {
            position = try XCTUnwrap(animation.positions(timestamp: 1 + 2.0 / 60 + Double(frame) / 120, project: project).first ?? nil)
        }
        XCTAssertEqual(position.x, 91.25, accuracy: 0.001, "60Hz and 120Hz must cover the same distance per second")
    }
    func testMovingCircleLoopsAndIndependentPathsHaveSameScreenSpeed() throws {
        let routes = [route("day|0|1"), route("day|1|1")]
        XCTAssertEqual(RouteSelection.paths(routes).count, 2)
        let short = RouteMotionPath(points: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 10)])
        let long = RouteMotionPath(points: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1000)])
        var cursor = RouteMotionCursor()
        let project: (Coordinate) -> CGPoint = { CGPoint(x: $0.longitude, y: $0.latitude) }
        XCTAssertEqual(try XCTUnwrap(cursor.advance(on: short, distance: 26, project: project)).x, 6, accuracy: 0.001)
        let animation = RouteMotionAnimation(); animation.reset(paths: [short, long])
        _ = animation.positions(timestamp: 0, project: project)
        let positions = animation.positions(timestamp: 0.1, project: project)
        XCTAssertEqual(try XCTUnwrap(positions[0]).x, 6, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(positions[1]).x, 6, accuracy: 0.001)
        let resumed = animation.positions(timestamp: 20, project: project)
        XCTAssertEqual(try XCTUnwrap(resumed[1]).x, 12, accuracy: 0.001, "Don't catch up with a huge jump after suspension")
        var zeroCursor = RouteMotionCursor()
        XCTAssertEqual(zeroCursor.advance(on: RouteMotionPath(points: [short.points[0], short.points[0]]), distance: 6, project: project), .zero)
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
