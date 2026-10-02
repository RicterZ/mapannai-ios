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
        XCTAssertTrue(RouteSelection.candidates(at: (50, 29), routes: [routes[0]]) { ($0.longitude, $0.latitude) }.isEmpty)
    }
    func testWiderHitAreaAndCachedProjection() {
        var projections = 0
        let index = RouteHitIndex(routes: [route("a")]) {
            projections += 1; return ($0.longitude, $0.latitude)
        }
        XCTAssertEqual(projections, 2)
        for _ in 0..<10 {
            XCTAssertEqual(index.candidates(at: (50, 27)).map(\.id), ["a"])
            XCTAssertTrue(index.candidates(at: (50, 29)).isEmpty)
            XCTAssertTrue(index.candidates(at: (-29, 0)).isEmpty)
        }
        XCTAssertEqual(projections, 2, "Repeated hits must not project the path again")
        let moved = RouteHitIndex(routes: [route("a")]) { ($0.longitude, $0.latitude + 100) }
        XCTAssertTrue(moved.candidates(at: (50, 0)).isEmpty)
        XCTAssertEqual(moved.candidates(at: (50, 100)).map(\.id), ["a"])
    }
    func testSpatialIndexProjectsOnlyNearbySegmentsAndSurvivesCameraChanges() throws {
        let points = (0...10000).map { Coordinate(latitude: 31, longitude: 120 + Double($0) * 0.0001) }
        let index = try RouteSpatialIndex(points: points)
        for center in [120.1, 120.5, 120.9] {
            let bounds = RouteGeoBounds(points: [Coordinate(latitude: 30.9999, longitude: center-0.0001),
                Coordinate(latitude: 31.0001, longitude: center+0.0001)], referenceLongitude: center)
            var calls = 0
            let distance = index.nearestDistance(at: CGPoint(x: 100, y: 200), bounds: bounds) {
                calls += 1
                return CGPoint(x: 100 + ($0.longitude-center)*100000, y: 200)
            }
            XCTAssertEqual(distance, 0, accuracy: 0.0001)
            XCTAssertLessThan(calls, 16, "A 10,000-segment route must not cause 10,000 SDK projections")
        }
    }
    func testSpatialIndexMatchesExactScreenPathUnderRotationAndZoom() throws {
        let points = (0...1000).map { i in Coordinate(latitude: 31 + sin(Double(i)*0.04)*0.01,
                                                    longitude: 121 + Double(i)*0.0001) }
        let index = try RouteSpatialIndex(points: points)
        for angle in [0.0, 0.7, 2.0] {
            for scale in [1000.0, 4000.0] {
                let c = cos(angle), s = sin(angle)
                let project: (Coordinate) -> CGPoint = {
                    let x = ($0.longitude-121)*scale, y = ($0.latitude-31)*scale
                    return CGPoint(x: x*c-y*s, y: x*s+y*c)
                }
                let tap = project(points[500])
                let r = RouteSelection.hitRadius
                let ground = [(-r,-r), (r,-r), (r,r), (-r,r)].map { offset in
                    let x = tap.x+offset.0, y = tap.y+offset.1
                    return Coordinate(latitude: 31+(-x*s+y*c)/scale, longitude: 121+(x*c+y*s)/scale)
                }
                let distance = index.nearestDistance(at: tap, bounds: RouteGeoBounds(points: ground, referenceLongitude: 121), project: project)
                XCTAssertEqual(distance, 0, accuracy: 0.00001)
            }
        }
    }
    func testSpatialIndexHandlesDateLineAndEmptyGeometry() throws {
        let a = Coordinate(latitude: 0, longitude: 179.9), b = Coordinate(latitude: 0, longitude: -179.9)
        let index = try RouteSpatialIndex(points: [a, b])
        let bounds = RouteGeoBounds(points: [Coordinate(latitude: -0.1, longitude: -179.99),
            Coordinate(latitude: 0.1, longitude: -179.95)], referenceLongitude: -179.97)
        let distance = index.nearestDistance(at: .zero, bounds: bounds) {
            CGPoint(x: RouteGeoBounds.longitudeDelta($0.longitude + 179.97)*100, y: 0)
        }
        XCTAssertEqual(distance, 0, accuracy: 0.000001)
        XCTAssertEqual(try RouteSpatialIndex(points: []).nearestDistance(at: .zero, bounds: bounds) { _ in .zero }, .infinity)
    }
    func testMotionEndpointWrapDoesNotProjectWholePath() throws {
        let path = RouteMotionPath(points: (0...10000).map { Coordinate(latitude: 0, longitude: Double($0)) })
        var cursor = RouteMotionCursor()
        _ = cursor.advance(on: path, distance: 9999.5) { CGPoint(x: $0.longitude, y: 0) }
        var calls = 0
        let point = try XCTUnwrap(cursor.advance(on: path, distance: 1) {
            calls += 1; return CGPoint(x: $0.longitude, y: 0)
        })
        XCTAssertEqual(point.x, 0.5, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(calls, 4, "Wrapping must visit only the endpoint and first segment")
        let duplicates = RouteMotionPath(points: Array(repeating: Coordinate(latitude: 0, longitude: 0), count: 10000))
        XCTAssertEqual(duplicates.points.count, 1)
    }
    func testPOIOverscanCoversLocalPanButNeedsRefreshAfterLongPan() {
        let viewport = RouteGeoBounds(points: [Coordinate(latitude: 30, longitude: 120), Coordinate(latitude: 31, longitude: 121)], referenceLongitude: 120)
        let coverage = viewport.expanded(factor: 1)
        XCTAssertTrue(coverage.contains(viewport.shifted(0.5)))
        XCTAssertFalse(coverage.contains(viewport.shifted(2)))
        XCTAssertEqual(coverage.corners.count, 4)
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
        XCTAssertEqual(RouteMotionAnimation.pointsPerSecond, 90, accuracy: 0.001, "The requested 1.5× speed is 90pt/s")
        XCTAssertEqual(position.x, 90, accuracy: 0.001)
        // Zoom retains the same segment/fraction; only the next frame's travel is added.
        scale = 2
        position = try XCTUnwrap(animation.positions(timestamp: 1 + 1.0 / 60, project: project).first ?? nil)
        XCTAssertEqual(position.x, 181.5, accuracy: 0.001)
        scale = 0.5
        position = try XCTUnwrap(animation.positions(timestamp: 1 + 2.0 / 60, project: project).first ?? nil)
        XCTAssertEqual(position.x, 46.875, accuracy: 0.001)
        for frame in 1...120 {
            position = try XCTUnwrap(animation.positions(timestamp: 1 + 2.0 / 60 + Double(frame) / 120, project: project).first ?? nil)
        }
        XCTAssertEqual(position.x, 136.875, accuracy: 0.001, "60Hz and 120Hz must cover the same distance per second")
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
        XCTAssertEqual(try XCTUnwrap(positions[0]).x, 9, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(positions[1]).x, 9, accuracy: 0.001)
        let resumed = animation.positions(timestamp: 20, project: project)
        XCTAssertEqual(try XCTUnwrap(resumed[1]).x, 18, accuracy: 0.001, "Don't catch up with a huge jump after suspension")
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
