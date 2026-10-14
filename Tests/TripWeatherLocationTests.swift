import XCTest
@testable import MapAnNai

final class TripWeatherLocationTests: XCTestCase {
    func testSingleMarkerPreservesExactCoordinate() {
        let stop = point("only", 31.234567, 121.456789)
        XCTAssertEqual(TripWeatherLocation.representative([stop]), stop.coordinate)
    }
    private func point(_ id: String, _ lat: Double, _ lon: Double) -> TripWeatherLocation.Point {
        .init(id: id, coordinate: .init(latitude: lat, longitude: lon))
    }
    func testRemoteAirportLosesToThreeCityStopsAndDuplicatesDoNotVote() throws {
        let airport = point("airport", 40, 116)
        let city = [point("b", 31.2, 121.4), point("c", 31.21, 121.41), point("d", 31.22, 121.42)]
        let result = try XCTUnwrap(TripWeatherLocation.representative([airport, airport, airport, airport] + city))
        XCTAssertEqual(result.latitude, 31.21, accuracy: 0.001)
        XCTAssertEqual(result.longitude, 121.41, accuracy: 0.001)
        XCTAssertEqual(result, TripWeatherLocation.representative(Array((city + [airport]).reversed())))
    }
    func testCompactnessThenStableIDBreakTies() throws {
        let points = [point("a", 40, 116), point("b", 40.1, 116), point("c", 31, 121), point("d", 31.01, 121)]
        XCTAssertEqual(try XCTUnwrap(TripWeatherLocation.representative(points)).latitude, 31.005, accuracy: 0.001)
        XCTAssertEqual(TripWeatherLocation.representative([points[2], points[0]]), points[0].coordinate)
    }
    func testDateLineAndInvalidOrEmptyInput() throws {
        let result = try XCTUnwrap(TripWeatherLocation.representative([point("a", 0, 179.95), point("b", 0, -179.95)]))
        XCTAssertEqual(abs(result.longitude), 180, accuracy: 0.001)
        XCTAssertNil(TripWeatherLocation.representative([]))
        XCTAssertNil(TripWeatherLocation.representative([point("bad", .nan, 0)]))
    }
}
