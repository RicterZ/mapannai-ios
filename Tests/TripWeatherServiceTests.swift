import XCTest
@testable import MapAnNai

final class TripWeatherServiceTests: XCTestCase {
    func testWeatherConditionNamesFollowCodesAndUnknownIsHidden() {
        for (code, name) in [(0, "晴"), (2, "多云"), (3, "阴"), (61, "小雨"), (75, "大雪"), (95, "雷雨")] {
            XCTAssertEqual(TripDayWeather(date: "test", weatherCode: code, minimumCelsius: nil, maximumCelsius: nil, precipitationProbability: nil).conditionName, name)
        }
        XCTAssertNil(TripDayWeather(date: "test", weatherCode: 999, minimumCelsius: nil, maximumCelsius: nil, precipitationProbability: nil).conditionName)
    }
    func testTemperatureRangeRequiresCompleteFiniteOrderedValues() {
        func weather(_ low: Double?, _ high: Double?) -> TripDayWeather {
            TripDayWeather(date: "2026-10-16", weatherCode: 0, minimumCelsius: low, maximumCelsius: high, precipitationProbability: nil)
        }
        XCTAssertEqual(weather(16.6, 24.2).temperatureRange, "17°~24°")
        XCTAssertEqual(weather(-5, -1).temperatureRange, "-5°~-1°")
        XCTAssertNil(weather(nil, 24).temperatureRange)
        XCTAssertNil(weather(.nan, 24).temperatureRange)
        XCTAssertNil(weather(25, 24).temperatureRange)
    }

    func testTokyoHistoryResolvesTimeZoneWithoutAppleGeocoding() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); MockURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = TripWeatherService(session: URLSession(configuration: configuration), cacheDirectory: directory)
        MockURLProtocol.handler = { request in
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "timezone" }?.value, "auto")
            XCTAssertEqual(request.url?.host, "archive-api.open-meteo.com")
            return (200, Data(#"{"timezone":"Asia/Tokyo","daily":{"time":["2024-05-01"],"weather_code":[63],"temperature_2m_min":[12.4],"temperature_2m_max":[19.9]}}"#.utf8))
        }
        let coordinate = Coordinate(latitude: 35.6762, longitude: 139.6503)
        let weather = try await service.forecast(for: "2024-05-01", at: coordinate)
        XCTAssertEqual(weather?.weatherCode, 63)
        let zone = await service.cachedTimeZone(at: coordinate)
        XCTAssertEqual(zone?.identifier, "Asia/Tokyo")
    }
    func testHistoricalWeatherUsesArchiveAndPersistsWithoutRefetching() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); MockURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let coordinate = Coordinate(latitude: 35.68, longitude: 139.69)
        let zone = TimeZone(identifier: "Asia/Tokyo")!
        let now = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "archive-api.open-meteo.com")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "start_date" }?.value, "2024-05-01")
            XCTAssertEqual(query.first { $0.name == "end_date" }?.value, "2024-05-01")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data(#"{"daily":{"time":["2024-05-01"],"weather_code":[63],"temperature_2m_min":[12.4],"temperature_2m_max":[19.9]}}"#.utf8))
        }
        let service = TripWeatherService(session: session, cacheDirectory: directory)
        let weather = try await service.forecast(for: "2024-05-01", at: coordinate, timeZone: zone, now: now)
        XCTAssertEqual(weather?.weatherCode, 63)
        XCTAssertNil(weather?.precipitationProbability)
        MockURLProtocol.handler = { _ in
            XCTFail("Historical cache must not be refreshed")
            throw URLError(.notConnectedToInternet)
        }
        let restored = TripWeatherService(session: session, cacheDirectory: directory)
        let cached = try await restored.forecast(for: "2024-05-01", at: coordinate, timeZone: zone, now: now)
        XCTAssertEqual(cached, weather)
    }

    func testRecentHistoryUsesPastDaysAndMissingCodeIsNotCached() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory); MockURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = TripWeatherService(session: URLSession(configuration: configuration), cacheDirectory: directory)
        let coordinate = Coordinate(latitude: 35, longitude: 140)
        let now = ISO8601DateFormatter().date(from: "2026-10-16T12:00:00Z")!
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.open-meteo.com")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            XCTAssertEqual(query.first { $0.name == "past_days" }?.value, "5")
            return (200, Data(#"{"daily":{"time":["2026-10-15"],"weather_code":[null],"temperature_2m_min":[null],"temperature_2m_max":[null]}}"#.utf8))
        }
        let weather = try await service.forecast(for: "2026-10-15", at: coordinate, timeZone: TimeZone(secondsFromGMT: 0)!, now: now)
        XCTAssertNil(weather)
        let cached = await service.cachedWeather(for: "2026-10-15", at: coordinate)
        XCTAssertNil(cached)
    }
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
