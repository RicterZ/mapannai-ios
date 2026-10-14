import XCTest
@testable import MapAnNai

final class TripWeatherServiceTests: XCTestCase {
    func testRefreshFreezesHistoryAndPreservesMissingForecast() async throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let now = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
        let past = TripDayWeather(date: "2026-10-15", weatherCode: 61, minimumCelsius: 10,
            maximumCelsius: 20, precipitationProbability: 80)
        let future = TripDayWeather(date: "2026-10-17", weatherCode: 3, minimumCelsius: 10,
            maximumCelsius: 20, precipitationProbability: 10)
        let old = TripWeatherService.Snapshot(timeZone: zone.identifier,
            days: [past.date: past, future.date: future], fetched: now)
        let daily = TripWeatherService.Daily(time: [past.date, "2026-10-16", future.date],
            weather_code: [0, 0, nil], temperature_2m_min: [11, 12, nil],
            temperature_2m_max: [22, 23, nil], precipitation_probability_max: [0, 0, nil])
        let merged = try await TripWeatherService.merge(old, daily: daily, timeZone: zone, now: now)
        XCTAssertEqual(merged.days[past.date], past)
        XCTAssertEqual(merged.days[future.date], future)
        XCTAssertEqual(merged.days["2026-10-16"]?.weatherCode, 0)
    }
    func testSevenDayWindowUsesDestinationCalendar() {
        let now = ISO8601DateFormatter().date(from: "2026-10-15T23:30:00Z")!
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertFalse(TripWeatherService.isInForecastWindow("2026-10-15", now: now, timeZone: zone))
        XCTAssertTrue(TripWeatherService.isInForecastWindow("2026-10-16", now: now, timeZone: zone))
        XCTAssertTrue(TripWeatherService.isInForecastWindow("2026-10-22", now: now, timeZone: zone))
        XCTAssertFalse(TripWeatherService.isInForecastWindow("2026-10-23", now: now, timeZone: zone))
        XCTAssertFalse(TripWeatherService.isInForecastWindow("2026-02-30", now: now, timeZone: zone))
    }

    func testDailyDecodingPreservesMissingValuesAndRejectsMismatchedArrays() throws {
        let data = Data(#"{"time":["2026-10-16"],"weather_code":[3],"temperature_2m_min":[null],"temperature_2m_max":[22.5],"precipitation_probability_max":[40]}"#.utf8)
        let daily = try JSONDecoder().decode(TripWeatherService.Daily.self, from: data)
        let weather = try XCTUnwrap(daily.weather(on: "2026-10-16"))
        XCTAssertNil(weather.minimumCelsius)
        XCTAssertEqual(weather.maximumCelsius, 22.5)
        XCTAssertEqual(weather.precipitationProbability, 40)
        XCTAssertNil(try daily.weather(on: "2026-10-17"))
        let invalid = TripWeatherService.Daily(time: ["2026-10-16"], weather_code: [],
            temperature_2m_min: [], temperature_2m_max: [], precipitation_probability_max: [])
        XCTAssertThrowsError(try invalid.weather(on: "2026-10-16"))
    }
}
