import XCTest
@testable import MapAnNai

final class JourneyArchiveOrderingTests: XCTestCase {
    func testYearBrowseIncludesTopAndSortsNewestFirstWithStableTies() {
        let values = [trip("old", "2025-01-01"), trip("b", "2025-12-01"),
                      trip("a", "2025-12-01"), trip("other", "2026-01-01")]
        XCTAssertEqual(JourneyArchiveOrdering.trips(in: 2025, from: values).map(\.id), ["a", "b", "old"])
        XCTAssertTrue(JourneyArchiveOrdering.trips(in: 2024, from: values).isEmpty)
    }

    func testYearPoseUsesDrawingBoundsAndClipProtectsHeading() {
        let pose = ArchiveYearPose(slot: CGRect(x: 16, y: 300, width: 360, height: 88))
        XCTAssertEqual(pose.frame, CGRect(x: 16, y: 300, width: 360, height: 204))
        let clip = ArchiveYearMotion.cardClip(heading: CGRect(x: 16, y: 20, width: 360, height: 70),
            size: CGSize(width: 392, height: 800))
        XCTAssertEqual(clip.minY, 114)
        XCTAssertEqual(clip.maxY, 800)
    }
    private func trip(_ id: String, _ start: String, _ end: String? = nil) -> Trip {
        Trip(id: id, name: id, startDate: start, endDate: end ?? start, days: [])
    }
    func testYearGroupsExcludeTopAndRemainNewestFirstWithoutFutureTrips() {
        let trips = [trip("top", "2026-10-01"), trip("same", "2026-08-02"),
                     trip("a", "2025-12-01"), trip("b", "2025-01-01"), trip("old", "2024-03-01")]
        let sorted = JourneyArchiveOrdering.sorted(trips, today: "2026-10-12")
        XCTAssertEqual(JourneyArchiveOrdering.yearGroups(sorted, today: "2026-10-12"), [
            1: JourneyArchiveYearGroup(year: 2026, count: 1),
            2: JourneyArchiveYearGroup(year: 2025, count: 2),
            4: JourneyArchiveYearGroup(year: 2024, count: 1)])
        XCTAssertTrue(JourneyArchiveOrdering.yearGroups([trips[0]], today: "2026-10-12").isEmpty)
    }
    func testYearGroupsDoNotReorderOngoingOrUpcomingTopCards() {
        let trips = [trip("ongoing", "2026-10-01", "2026-10-20"), trip("future", "2027-01-01"), trip("past", "2025-12-01")]
        let sorted = JourneyArchiveOrdering.sorted(trips, today: "2026-10-12")
        XCTAssertEqual(sorted.map(\.id), ["ongoing", "future", "past"])
        XCTAssertEqual(JourneyArchiveOrdering.yearGroups(sorted, today: "2026-10-12"), [
            1: JourneyArchiveYearGroup(year: 2027, count: 1), 2: JourneyArchiveYearGroup(year: 2025, count: 1)])
    }
    func testOngoingWinsOverNearestUpcomingThenRemainderIsNewestFirst() {
        let trips = [trip("old", "2026-01-01"), trip("near", "2026-10-15"),
                     trip("far", "2027-01-01"), trip("recent", "2026-10-01"),
                     trip("ongoing", "2026-09-01", "2026-11-01")]
        XCTAssertEqual(JourneyArchiveOrdering.sorted(trips, today: "2026-10-12").map(\.id),
                       ["ongoing", "far", "near", "recent", "old"])
    }
    func testAllOngoingTripsAreTopNewestFirstWithStableIDs() {
        let trips = [trip("older", "2026-09-01", "2026-10-12"),
                     trip("b", "2026-10-12", "2026-10-20"),
                     trip("a", "2026-10-12", "2026-10-15"),
                     trip("future", "2026-10-13"), trip("past", "2026-10-11")]
        XCTAssertEqual(JourneyArchiveOrdering.topTrips(trips, today: "2026-10-12").map(\.id),
                       ["a", "b", "older"])
        XCTAssertEqual(JourneyArchiveOrdering.sorted(trips, today: "2026-10-12").map(\.id),
                       ["a", "b", "older", "future", "past"])
    }
    func testWithoutOngoingNearestUpcomingWinsOverMoreRecentPast() {
        XCTAssertEqual(JourneyArchiveOrdering.topTrips([
            trip("past", "2026-10-11"), trip("far", "2026-12-01"), trip("near", "2026-10-20")
        ], today: "2026-10-12").map(\.id), ["near"])
    }
    func testTodayDepartureWinsOverTomorrow() {
        XCTAssertEqual(JourneyArchiveOrdering.sorted([
            trip("tomorrow", "2026-10-13"), trip("today", "2026-10-12")
        ], today: "2026-10-12").map(\.id), ["today", "tomorrow"])
    }
    func testWithoutFutureTopIsClosestDepartureThenNewestFirst() {
        XCTAssertEqual(JourneyArchiveOrdering.sorted([
            trip("old", "2026-01-01"), trip("recent", "2026-10-01"), trip("middle", "2026-09-01")
        ], today: "2026-10-12").map(\.id), ["recent", "middle", "old"])
    }
    func testSameDatesUseStableIDsAndTopIsNotDuplicated() {
        XCTAssertEqual(JourneyArchiveOrdering.sorted([
            trip("b", "2026-10-15"), trip("a", "2026-10-15"), trip("c", "2026-10-15")
        ], today: "2026-10-12").map(\.id), ["a", "b", "c"])
        XCTAssertTrue(JourneyArchiveOrdering.sorted([], today: "2026-10-12").isEmpty)
    }
}
