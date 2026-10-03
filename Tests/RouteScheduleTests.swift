import XCTest
@testable import MapAnNai

final class RouteScheduleTests: XCTestCase {
    private let json = #"{"id":"day","tripId":"trip","date":"2026-10-03","markerIds":["a","b"],"chains":[["a","b"]],"routeChains":[{"id":"route","stops":[{"id":"visit-a","markerId":"a","startTime":"09:30","durationMinutes":60},{"id":"visit-b","markerId":"b"}],"legs":[{"fromStopId":"visit-a","toStopId":"visit-b","mode":"train","serviceNumber":"G123","startTime":"10:30","durationMinutes":30,"note":"2号站台"}]}]}"#
    func testOldServerAndScheduledServerDecodeAndRejectStaleOrder() throws {
        var day = try JSONDecoder().decode(TripDay.self, from: Data(json.utf8))
        let route = try XCTUnwrap(day.scheduledRoute(at: 0))
        XCTAssertEqual(route.leg(at: 0)?.serviceNumber, "G123")
        XCTAssertEqual(route.stops[0].summary, "09:30 · 1小时")
        XCTAssertNil(route.leg(at: 1))
        day.chains = [["b", "a"]]
        XCTAssertNil(day.scheduledRoute(at: 0)) // Never display the old traffic on a different pair.
        let old = #"{"id":"old","tripId":"trip","date":"2026-10-03","markerIds":[],"chains":[]}"#
        XCTAssertNil(try JSONDecoder().decode(TripDay.self, from: Data(old.utf8)).routeChains)
    }
    @MainActor func testMetadataPatchUsesVisitIDsAndPublishesResponseWithoutReplacingGeometry() async throws {
        let day = try JSONDecoder().decode(TripDay.self, from: Data(json.utf8))
        let route = try XCTUnwrap(day.scheduledRoute(at: 0))
        let defaults = UserDefaults.standard, previousURL = UserDefaults.standard.object(forKey: "baseURL")
        defaults.set("", forKey: "baseURL")
        let settings = Settings()
        if let previousURL { defaults.set(previousURL, forKey: "baseURL") } else { defaults.removeObject(forKey: "baseURL") }
        let store = AppStore(settings: settings, demo: false)
        store.trips = [Trip(id: "trip", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        store.displayRoutes = [DisplayRoute(id: "geometry", dayID: "day", tripID: "trip", colorIndex: 0, points: [Coordinate(latitude: 31, longitude: 121)], isPlanned: true, distance: 500)]
        var updated = day
        updated.routeChains?[0].legs[0].serviceNumber = "G456"
        let response = try JSONEncoder().encode(updated)
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://example.invalid", token: "", session: URLSession(configuration: configuration))
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/trips/trip/days/day/chains/route")
            let body = try! JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            let leg = (body["legs"] as! [[String: Any]])[0]
            XCTAssertEqual(leg["fromStopId"] as? String, "visit-a")
            XCTAssertEqual(leg["serviceNumber"] as? String, "G456")
            return (200, response)
        }
        defer { MockURLProtocol.handler = nil }
        let request = RouteScheduleRequest(day: day, route: route, position: 0, isTransport: true, fromTitle: "A", toTitle: "B")
        let success = await store.saveRouteSchedule(request, patch: ["legs": [["fromStopId": "visit-a", "toStopId": "visit-b", "serviceNumber": "G456"]]], using: client)
        XCTAssertTrue(success)
        XCTAssertEqual(store.trips[0].days[0].routeChains?[0].legs[0].serviceNumber, "G456")
        XCTAssertEqual(store.displayRoutes.first?.distance, 500)
        XCTAssertEqual(store.displayRoutes.first?.id, "geometry")
    }
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(buffer, count: count)
        }
        return data
    }

}
