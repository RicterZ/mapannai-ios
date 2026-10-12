import XCTest
@testable import MapAnNai

final class JourneyDaySummaryTests: XCTestCase {
    private let markers = ["a", "b", "c", "d"].map {
        Marker(id: $0, coordinates: Coordinate(latitude: 0, longitude: 0),
            content: MarkerContent(id: $0, title: $0.uppercased(), headerImage: $0 == "b" ? "https://example.invalid/b.jpg" : nil, markdownContent: ""))
    }
    func testIndependentRoutesAndUnorderedMembersAreNotJoinedAsOneRoute() {
        var day = TripDay(id: "d", tripId: "t", date: "2026-10-01", title: " 第 1 天 ",
            markerIds: ["d", "c", "b", "a"], chains: [["a", "b"], ["c"]])
        let summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertNil(summary.theme)
        XCTAssertEqual(summary.places, "A → B\nC\n另有1个地点")
        XCTAssertEqual(summary.routePreviews, [["A", "B"], ["C"]])
        XCTAssertEqual(summary.unplannedPlaces, ["D"])
        XCTAssertEqual(summary.coverURL?.host, "example.invalid")
        XCTAssertEqual(summary.coverTitle, "B")
        XCTAssertEqual(summary.timing, "0项时间安排"); XCTAssertNil(summary.transport)
        day.chains = []
        XCTAssertTrue(JourneyDaySummary(day: day, index: 0, markers: markers).routePreviews.isEmpty)
        XCTAssertEqual(JourneyDaySummary(day: day, index: 0, markers: markers).unplannedPlaces, ["D", "C", "B", "A"])
        XCTAssertEqual(JourneyDaySummary(day: day, index: 0, markers: markers).places, "D · C · B · A")
    }
    func testChaptersSkipCoverAndPreviouslySelectedPhotos() {
        var places = markers
        places[0].content.headerImage = "https://example.invalid/hotel.jpg"
        places[2].content.headerImage = "https://example.invalid/b.jpg"
        places[3].content.headerImage = "https://example.invalid/park.jpg"
        let days = [
            TripDay(id: "1", tripId: "t", date: "2026-10-01", markerIds: ["a", "b"], chains: [["a", "b"]]),
            TripDay(id: "2", tripId: "t", date: "2026-10-02", markerIds: ["a", "c", "d"], chains: [["a", "c", "d"]]),
            TripDay(id: "3", tripId: "t", date: "2026-10-03", markerIds: ["a", "b", "d"], chains: [])
        ]
        let excluded: Set<URL> = [URL(string: "https://example.invalid/hotel.jpg")!]
        let summaries = JourneyDaySummary.chapters(days: days, markers: places, excludingPhotos: excluded)
        XCTAssertEqual(summaries.map(\.coverTitle), ["B", "D", nil])
        XCTAssertEqual(summaries.map { $0.coverURL?.lastPathComponent }, ["b.jpg", "park.jpg", nil])
        XCTAssertEqual(JourneyDaySummary.chapters(days: days, markers: places, excludingPhotos: excluded).map(\.coverURL), summaries.map(\.coverURL))
        XCTAssertEqual(JourneyDaySummary.chapters(days: days, markers: places).first?.coverTitle, "A")
    }

    func testMissingThemeAndPhotoRemainAbsent() {
        var day = TripDay(id: "d", tripId: "t", date: "2026-10-01", title: "  ", markerIds: ["a"], chains: [])
        let summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertNil(summary.theme)
        XCTAssertNil(summary.coverURL)
        XCTAssertNil(summary.coverTitle)
        XCTAssertEqual(summary.places, "A")
        day.title = day.date
        XCTAssertNil(JourneyDaySummary(day: day, index: 0, markers: markers).theme)
    }

    func testOnlyActiveAdjacentTransportAndActualFirstStopTimeAppear() {
        let stops = [ChainStop(id: "va", markerId: "a"), ChainStop(id: "vb", markerId: "b", startTime: "10:30")]
        var day = TripDay(id: "d", tripId: "t", date: "2026-10-01", markerIds: ["a", "b"], chains: [["a", "b"]],
            routeChains: [RouteChain(id: "r", stops: stops, legs: [ChainLeg(fromStopId: "va", toStopId: "vb", mode: .subway)],
                inactiveLegs: [ChainLeg(fromStopId: "vb", toStopId: "va", mode: .flight)])])
        var summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertEqual(summary.timing, "1项时间安排")
        XCTAssertEqual(summary.transport, "地铁")
        day.routeChains?[0].stops[0].startTime = "09:30"
        summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertEqual(summary.timing, "09:30 首站")
        day.chains = [["b", "a"]]
        summary = JourneyDaySummary(day: day, index: 0, markers: markers)
        XCTAssertEqual(summary.timing, "0项时间安排"); XCTAssertNil(summary.transport)
    }
    func testCountsVisitsAndOnlyAdjacentTransportOnceEach() {
        let stops = [ChainStop(id: "a", markerId: "a", durationMinutes: 30),
                     ChainStop(id: "b", markerId: "b", startTime: "10:00", durationMinutes: 45),
                     ChainStop(id: "c", markerId: "c")]
        let day = TripDay(id: "d", tripId: "t", date: "2026-10-01", markerIds: ["a", "b", "c"], chains: [["a", "b", "c"]],
            routeChains: [RouteChain(id: "r", stops: stops, legs: [
                ChainLeg(fromStopId: "a", toStopId: "b", mode: .train, startTime: "09:00", durationMinutes: 20),
                ChainLeg(fromStopId: "b", toStopId: "c", mode: .taxi, durationMinutes: 10),
                ChainLeg(fromStopId: "a", toStopId: "c", mode: .walking, startTime: "12:00")],
                inactiveLegs: [ChainLeg(fromStopId: "c", toStopId: "a", mode: .flight, durationMinutes: 60)])])
        XCTAssertEqual(JourneyDaySummary(day: day, index: 0, markers: markers).timing, "4项时间安排")
        let empty = TripDay(id: "empty", tripId: "t", date: "2026-10-02", markerIds: [], chains: [])
        XCTAssertEqual(JourneyDaySummary(day: empty, index: 1, markers: []).timing, "0项时间安排")
    }

}
