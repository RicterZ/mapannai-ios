import XCTest
@testable import MapAnNai

final class TripWeatherLocationTests: XCTestCase {
    func testEmptyDayUsesOnlyFirstDestinationIncludingLegacyDestination() {
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-15", markerIds: [], chains: [])
        let first = TripDestination(name: "东京", latitude: 35.6762, longitude: 139.6503)
        let second = TripDestination(name: "北京", latitude: 39.9, longitude: 116.4)
        var trip = Trip(id: "t", name: "Trip", startDate: day.date, endDate: day.date, days: [day])
        XCTAssertTrue(TripWeatherLocation.points(day: day, trip: trip, markers: []).isEmpty)
        trip.destination = first
        let fallback = TripWeatherLocation.points(day: day, trip: trip, markers: [])
        XCTAssertEqual(fallback.first?.coordinate, Coordinate(latitude: first.latitude, longitude: first.longitude))
        trip.destinations = [first, second]
        XCTAssertEqual(TripWeatherLocation.points(day: day, trip: trip, markers: []), fallback)
        trip.destinations = []
        XCTAssertTrue(TripWeatherLocation.points(day: day, trip: trip, markers: []).isEmpty)
    }
    func testDayMembersAndRouteMembersTakePriorityOverDestination() {
        var day = TripDay(id: "d", tripId: "t", date: "2026-10-15", markerIds: ["p"], chains: [])
        let trip = Trip(id: "t", name: "Trip", startDate: day.date, endDate: day.date, days: [day],
            destinations: [TripDestination(name: "东京", latitude: 35, longitude: 139)])
        let marker = Marker(id: "p", coordinates: Coordinate(latitude: 31, longitude: 121),
            content: MarkerContent(id: "p", title: "Point", markdownContent: ""))
        XCTAssertEqual(TripWeatherLocation.points(day: day, trip: trip, markers: [marker]).first?.coordinate, marker.coordinates)
        day.markerIds = []; day.chains = [["p"]]
        XCTAssertEqual(TripWeatherLocation.points(day: day, trip: trip, markers: [marker]).first?.coordinate, marker.coordinates)
        XCTAssertTrue(TripWeatherLocation.points(day: day, trip: trip, markers: []).isEmpty,
            "Unresolved day members must not silently change weather location")
    }

    func testAsyncLocationCacheTracksCoordinatesAndMembership() async {
        let cache = TripWeatherLocationCache()
        let first = point("a", 31.2, 121.4)
        let moved = point("a", 40, 116)
        let initial = await cache.representative([first])
        let repeated = await cache.representative([first])
        let updated = await cache.representative([moved])
        let empty = await cache.representative([])
        XCTAssertEqual(initial, first.coordinate)
        XCTAssertEqual(repeated, initial)
        XCTAssertEqual(updated, moved.coordinate)
        XCTAssertNil(empty)
    }
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
