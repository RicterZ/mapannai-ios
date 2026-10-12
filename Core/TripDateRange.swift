import Foundation

/// Calendar-day range; counts include both endpoints, even across daylight saving changes.
struct TripDateRange: Equatable {
    var start: Date
    var end: Date
    var choosingEnd = false
    let calendar: Calendar

    init(start: Date = .now, end: Date? = nil, calendar: Calendar = Calendar(identifier: .gregorian)) {
        self.calendar = calendar
        let a = calendar.startOfDay(for: start)
        let b = calendar.startOfDay(for: end ?? start)
        self.start = min(a, b)
        self.end = max(a, b)
    }
    var dayCount: Int { (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1 }
    var isValid: Bool { (1...367).contains(dayCount) }
    var apiStart: Date { Self.apiDate(start, calendar: calendar) }
    var apiEnd: Date { Self.apiDate(end, calendar: calendar) }

    /// Existing API helpers represent date-only values as UTC midnight.
    static func apiDate(_ day: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        return .fromDay(String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!))
    }
    init(savedStart: Date, savedEnd: Date, calendar: Calendar = Calendar(identifier: .gregorian)) {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        let a = calendar.date(from: utc.dateComponents([.year, .month, .day], from: savedStart))!
        let b = calendar.date(from: utc.dateComponents([.year, .month, .day], from: savedEnd))!
        self.init(start: a, end: b, calendar: calendar)
    }

    mutating func select(_ date: Date) {
        let day = calendar.startOfDay(for: date)
        if choosingEnd {
            end = max(start, day)
            start = min(start, day)
        } else {
            start = day
            end = day
        }
        choosingEnd.toggle()
    }
}
