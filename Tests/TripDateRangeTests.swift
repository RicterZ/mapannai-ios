import XCTest
@testable import MapAnNai

final class TripDateRangeTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return value
    }
    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }
    func testReverseSelectionAndNewSelectionResetRange() {
        var range = TripDateRange(start: day(2026, 10, 12), calendar: calendar)
        range.select(day(2026, 10, 26)); XCTAssertTrue(range.choosingEnd)
        range.select(day(2026, 10, 23))
        XCTAssertEqual(range.start, day(2026, 10, 23)); XCTAssertEqual(range.end, day(2026, 10, 26))
        XCTAssertEqual(range.dayCount, 4); XCTAssertFalse(range.choosingEnd)
        range.select(day(2026, 11, 1))
        XCTAssertEqual(range.start, range.end); XCTAssertEqual(range.dayCount, 1)
    }
    func testSameDayAndCrossYearIncludeBothEndpoints() {
        var range = TripDateRange(start: day(2026, 12, 30), calendar: calendar)
        range.select(day(2026, 12, 30)); range.select(day(2026, 12, 30))
        XCTAssertEqual(range.dayCount, 1)
        range.select(day(2026, 12, 30)); range.select(day(2027, 1, 2))
        XCTAssertEqual(range.dayCount, 4)
    }
    func testDaylightSavingDoesNotChangeDayCount() {
        XCTAssertEqual(TripDateRange(start: day(2026, 3, 7), end: day(2026, 3, 9), calendar: calendar).dayCount, 3)
        XCTAssertEqual(TripDateRange(start: day(2026, 10, 31), end: day(2026, 11, 2), calendar: calendar).dayCount, 3)
    }
    func testRangeLimitIs367CalendarDays() {
        let start = day(2026, 1, 1)
        XCTAssertTrue(TripDateRange(start: start, end: calendar.date(byAdding: .day, value: 366, to: start)!, calendar: calendar).isValid)
        XCTAssertFalse(TripDateRange(start: start, end: calendar.date(byAdding: .day, value: 367, to: start)!, calendar: calendar).isValid)
    }
    func testAPIDatesAndRecoveryPreserveSelectedDaysInBothHemispheres() {
        for zone in ["America/Los_Angeles", "Asia/Shanghai"] {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: zone)!
            let start = cal.date(from: DateComponents(year: 2026, month: 10, day: 23))!
            let end = cal.date(from: DateComponents(year: 2026, month: 10, day: 26))!
            let range = TripDateRange(start: start, end: end, calendar: cal)
            XCTAssertEqual(range.apiStart.dayString, "2026-10-23")
            XCTAssertEqual(range.apiEnd.dayString, "2026-10-26")
            let restored = TripDateRange(savedStart: range.apiStart, savedEnd: range.apiEnd, calendar: cal)
            XCTAssertEqual(restored.start, start); XCTAssertEqual(restored.end, end)
        }
    }
    func testRecoveredRangeIsNormalizedToLocalDays() {
        let start = day(2026, 10, 23)
        let end = day(2026, 10, 26)
        let range = TripDateRange(start: end.addingTimeInterval(3600), end: start.addingTimeInterval(7200), calendar: calendar)
        XCTAssertEqual(range.start, start); XCTAssertEqual(range.end, end)
    }
}
