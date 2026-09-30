import XCTest
@testable import MapAnNai

private struct DecodeThreadProbe: Decodable {
    let decodedOnMain: Bool
    init(from decoder: Decoder) throws {
        decodedOnMain = Thread.isMainThread
        _ = try decoder.singleValueContainer().decode([Int].self)
    }
}

final class ConcurrencyTests: XCTestCase {
    @MainActor func testRequestFromUIActorDecodesAwayFromUIThread() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        MockURLProtocol.handler = { _ in (200, Data("[1,2,3]".utf8)) }
        let probe: DecodeThreadProbe = try await APIClient(baseURL: "https://thread-test.invalid", token: "", session: session).request("probe")
        XCTAssertFalse(probe.decodedOnMain)
        XCTAssertTrue(Thread.isMainThread, "Only result consumption returns to the UI thread")
    }
    @MainActor func testLargeGeometryKeepsEndpointsAndRawInputAndRejectsCancellation() async throws {
        let worker = RouteProcessing()
        let raw = (0..<20_000).map { RoutePoint(lat: 31 + Double($0) * 0.00001, lng: 121 + Double($0) * 0.00001) }
        let route = PlannedRoute(path: raw, distance: 42, duration: 10)
        let a = Coordinate(latitude: 31, longitude: 121), b = Coordinate(latitude: 31.2, longitude: 121.2)
        let points = try await worker.displayPoints(route, origin: a, destination: b)
        XCTAssertEqual(points.first, a); XCTAssertEqual(points.last, b)
        XCTAssertEqual(route.path, raw)
        let converted = try await worker.amapCoordinates(points)
        XCTAssertEqual(converted.count, points.count)
        XCTAssertTrue(converted.allSatisfy(\.isValid))
        let cancelled = Task { try await worker.amapCoordinates(points) }
        cancelled.cancel()
        do { _ = try await cancelled.value; XCTFail("Cancelled geometry must not be committed") }
        catch is CancellationError {} catch { XCTFail("Unexpected cancellation result") }
    }
    @MainActor func testOnlyNewestRouteSelectionIsPublished() async throws {
        let store = AppStore(settings: Settings(), demo: true)
        let trip = try XCTUnwrap(store.trip)
        var many = trip
        many.days = (0..<80).map { i in
            TripDay(id: "large-\(i)", tripId: trip.id, date: "2026-10-01", markerIds: store.markers.map(\.id),
                    chains: Array(repeating: store.markers.map(\.id), count: 20))
        }
        store.select(trip: many, focus: false)
        store.select(trip: trip, day: trip.days[1], focus: false)
        await store.awaitRouteUpdates()
        XCTAssertFalse(store.displayRoutes.isEmpty)
        XCTAssertTrue(store.displayRoutes.allSatisfy { $0.dayID == trip.days[1].id })
    }
}
