import Combine
import XCTest
@testable import MapAnNai

private actor NoRouteRequests: MapServices {
    private(set) var requests = 0
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] { [] }
    func details(at coordinate: Coordinate) async throws -> Place { throw AppError.message("Unused") }
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TravelMode) async throws -> PlannedRoute {
        requests += 1
        throw AppError.message("Cached navigation must not request routes")
    }
}

final class RouteRedrawTests: XCTestCase {
    @MainActor func testReturningFromDayPublishesCachedGeometryWithoutTemporaryCurves() async throws {
        let settings = Settings(); let originalPlanning = settings.planning
        settings.planning = true
        defer { settings.planning = originalPlanning }
        let sample = AppStore(settings: settings, demo: true)
        await sample.awaitRouteUpdates()
        let trip = try XCTUnwrap(sample.trip)
        let cache = RouteCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let service = NoRouteRequests()
        let store = AppStore(settings: settings, demo: false, services: service, routeCache: cache)
        store.markers = sample.markers; store.trips = [trip]
        let processor = RouteProcessing()
        var expected: [String: [Coordinate]] = [:]
        for day in trip.days {
            for (chainIndex, chain) in day.chains.enumerated() {
                for index in 1..<chain.count {
                    let a = try XCTUnwrap(sample.markers.first { $0.id == chain[index - 1] })
                    let b = try XCTUnwrap(sample.markers.first { $0.id == chain[index] })
                    let route = PlannedRoute(path: [RoutePoint(lat: a.coordinates.latitude, lng: a.coordinates.longitude),
                        RoutePoint(lat: (a.coordinates.latitude + b.coordinates.latitude) / 2 + 0.002,
                                   lng: (a.coordinates.longitude + b.coordinates.longitude) / 2),
                        RoutePoint(lat: b.coordinates.latitude, lng: b.coordinates.longitude)], distance: 0, duration: 0)
                    let key = RouteCache.key(a.coordinates, b.coordinates, mode: settings.mode,
                        provider: store.mapConfiguration.directionsProvider, server: settings.baseURL)
                    await cache.put(route, key: key)
                    expected["\(day.id)|\(chainIndex)|\(index)|\(a.id)|\(b.id)"] = try await processor.displayPoints(route, origin: a.coordinates, destination: b.coordinates)
                }
            }
        }
        store.select(trip: trip, day: trip.days[0], focus: false)
        await store.awaitRouteUpdates()
        let cameraID = store.camera?.id
        var wrongFrames: [String] = []
        var publications = 0
        let observation = store.$displayRoutes.dropFirst().sink { routes in
            publications += 1
            for route in routes where route.points != expected[route.id] { wrongFrames.append(route.id) }
        }
        for _ in 0..<3 {
            store.select(trip: trip, focus: false)
            await store.awaitRouteUpdates()
            XCTAssertEqual(store.displayRoutes.count, expected.count)
            store.select(trip: trip, day: trip.days[0], focus: false)
            await store.awaitRouteUpdates()
        }
        observation.cancel()
        XCTAssertTrue(wrongFrames.isEmpty, "Intermediate curve snapshots were published: \(wrongFrames)")
        XCTAssertEqual(publications, 6, "Each navigation should publish exactly one complete route snapshot")
        XCTAssertEqual(store.camera?.id, cameraID)
        let requests = await service.requests
        XCTAssertEqual(requests, 0)
    }
    func testCachedGeometryRespectsEndpointsModeAndServerAndUpdatesColor() async throws {
        let processor = RouteProcessing()
        let cache = RouteCache(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString))
        let a = Coordinate(latitude: 31, longitude: 121), b = Coordinate(latitude: 31.01, longitude: 121.02)
        let markers = [Marker(id: "a", coordinates: a, content: MarkerContent(id: "a", markdownContent: "")),
                       Marker(id: "b", coordinates: b, content: MarkerContent(id: "b", markdownContent: ""))]
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-01", colorIndex: 2, markerIds: ["a", "b"], chains: [["a", "b"]])
        let segments = try await processor.build(days: [day], markers: markers, selectedTrip: nil, previous: [], preserve: true)
        let planned = PlannedRoute(path: [RoutePoint(lat: 31, lng: 121), RoutePoint(lat: 31.006, lng: 121.013),
            RoutePoint(lat: 31.01, lng: 121.02)], distance: nil, duration: nil)
        await cache.put(planned, key: RouteCache.key(a, b, mode: .walking, provider: .amap, server: "https://a.invalid"))
        let restored = try await processor.restoringCachedGeometry(segments, cache: cache, mode: .walking, provider: .amap, server: "https://a.invalid")
        XCTAssertTrue(try XCTUnwrap(restored.first).display.isPlanned)
        for (mode, server) in [(TravelMode.driving, "https://a.invalid"), (.walking, "https://b.invalid")] {
            let isolated = try await processor.restoringCachedGeometry(segments, cache: cache, mode: mode, provider: .amap, server: server)
            XCTAssertFalse(try XCTUnwrap(isolated.first).display.isPlanned)
        }
        var recolored = day; recolored.colorIndex = 4
        let rebuilt = try await processor.build(days: [recolored], markers: markers, selectedTrip: nil,
            previous: restored.map(\.display), preserve: true)
        XCTAssertEqual(rebuilt.first?.display.colorIndex, 4)
        XCTAssertEqual(rebuilt.first?.display.points, restored.first?.display.points)
        var moved = markers; moved[1].coordinates.longitude += 0.001
        let movedSegments = try await processor.build(days: [day], markers: moved, selectedTrip: nil,
            previous: restored.map(\.display), preserve: true)
        let movedRestored = try await processor.restoringCachedGeometry(movedSegments, cache: cache,
            mode: .walking, provider: .amap, server: "https://a.invalid")
        XCTAssertFalse(try XCTUnwrap(movedRestored.first).display.isPlanned)
        XCTAssertEqual(movedRestored.first?.display.points.last, moved[1].coordinates)
    }

    func testOverlayBatchKeepsIdentityAndRejectsCancelledConversion() async throws {
        let processor = RouteProcessing()
        let routes = (0..<4).map { index in
            DisplayRoute(id: "route-\(index)", dayID: "day", tripID: "trip", colorIndex: index,
                points: [Coordinate(latitude: 31, longitude: 121), Coordinate(latitude: 31.01, longitude: 121.02)], isPlanned: true)
        }
        let snapshot = routes.map(RouteOverlayGeometry.init)
        let converted = try await processor.amapSnapshot(snapshot)
        XCTAssertEqual(converted.map(\.geometry), snapshot)
        for (route, prepared) in zip(routes, converted) {
            XCTAssertEqual(prepared.coordinates, route.points.map(Coordinates.gcj))
        }
        var sameGeometry = routes[0]; sameGeometry.isPlanned = false
        XCTAssertEqual(RouteOverlayGeometry(sameGeometry), snapshot[0], "Selection/planning flags alone must not rebuild an overlay")
        sameGeometry.colorIndex += 1
        XCTAssertNotEqual(RouteOverlayGeometry(sameGeometry), snapshot[0])
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await processor.amapSnapshot(snapshot)
        }
        do { _ = try await cancelled.value; XCTFail("A stale conversion must not deliver a snapshot") }
        catch is CancellationError {} catch { XCTFail("Unexpected error: \(error)") }
    }

}
