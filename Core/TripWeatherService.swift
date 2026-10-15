import Foundation
import CryptoKit

struct TripDayWeather: Codable, Equatable {
    let date: String
    let weatherCode: Int?
    let minimumCelsius: Double?
    let maximumCelsius: Double?
    let precipitationProbability: Int?
}

// Separate from the authenticated map API: no app credentials are sent to Open-Meteo.
actor TripWeatherService {
    static let shared = TripWeatherService()
    struct Snapshot: Codable {
        var timeZone: String
        var days: [String: TripDayWeather]
        var fetched: Date
    }
    private let disk: TripWeatherDiskCache
    private var snapshots: [Coordinate: Snapshot] = [:]


    static let attributionURL = URL(string: "https://open-meteo.com/")!
    private let session: URLSession

    init(session: URLSession = .shared, cacheDirectory: URL? = nil) {
        self.session = session
        disk = TripWeatherDiskCache(directory: cacheDirectory)
    }

    func cachedWeather(for day: String, at coordinate: Coordinate) async -> TripDayWeather? {
        if snapshots[coordinate] == nil { snapshots[coordinate] = await disk.read(coordinate) }
        return snapshots[coordinate]?.days[day]
    }

    func cachedTimeZone(at coordinate: Coordinate) async -> TimeZone? {
        if snapshots[coordinate] == nil { snapshots[coordinate] = await disk.read(coordinate) }
        return snapshots[coordinate].flatMap { TimeZone(identifier: $0.timeZone) }
    }

    static func merge(_ old: Snapshot?, daily: Daily, timeZone: TimeZone, now: Date) throws -> Snapshot {
        var days = old?.days ?? [:]
        let today = JourneyArchiveOrdering.localDay(at: now, timeZone: timeZone)
        for date in daily.time where date >= today || days[date] == nil {
            guard let weather = try daily.weather(on: date), weather.weatherCode != nil else { continue }
            days[date] = weather
        }
        return Snapshot(timeZone: timeZone.identifier, days: days, fetched: now)
    }

    nonisolated static func isInForecastWindow(_ day: String, now: Date = .now, timeZone: TimeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day,
              let distance = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                  to: calendar.startOfDay(for: date)).day else { return false }
        return (0..<7).contains(distance)
    }

    func forecast(for day: String, at coordinate: Coordinate, timeZone requestedTimeZone: TimeZone? = nil,
                  now: Date = .now) async throws -> TripDayWeather? {
        guard coordinate.isValid else { throw URLError(.badURL) }
        let cached = await cachedWeather(for: day, at: coordinate)
        let knownZone = requestedTimeZone ?? snapshots[coordinate].flatMap { TimeZone(identifier: $0.timeZone) }
        let timeZone = knownZone ?? .current
        let today = JourneyArchiveOrdering.localDay(at: now, timeZone: timeZone)
        let historical = day < today
        if historical, cached != nil, knownZone != nil { return cached }
        let inWindow = (knownZone == nil ? [-86400.0, 0, 86400] : [0]).contains {
            Self.isInForecastWindow(day, now: now.addingTimeInterval($0), timeZone: timeZone)
        }
        guard historical || inWindow else { return cached }
        guard !historical || day >= "1940-01-01" else { return cached }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let cutoff = JourneyArchiveOrdering.localDay(at: calendar.date(byAdding: .day, value: -5, to: now)!, timeZone: timeZone)
        // Archive data lags several days; use forecast past-day data for the recent past.
        let useArchive = historical && day < cutoff
        if let entry = snapshots[coordinate], cached != nil,
           now.timeIntervalSince(entry.fetched) < 1800 { return cached }
        var url = URLComponents(string: useArchive ? "https://archive-api.open-meteo.com/v1/archive" : "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "timezone", value: knownZone?.identifier ?? "auto"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "daily", value: useArchive ? "weather_code,temperature_2m_min,temperature_2m_max" : "weather_code,temperature_2m_min,temperature_2m_max,precipitation_probability_max")
        ]
        if useArchive {
            url.queryItems! += [URLQueryItem(name: "start_date", value: day), URLQueryItem(name: "end_date", value: day)]
        } else {
            url.queryItems!.append(URLQueryItem(name: "forecast_days", value: "7"))
            if historical { url.queryItems!.append(URLQueryItem(name: "past_days", value: "5")) }
        }
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let result = try JSONDecoder().decode(Response.self, from: data)
        guard let destinationZone = result.timezone.flatMap({ TimeZone(identifier: $0) }) ?? knownZone else {
            throw URLError(.cannotParseResponse)
        }
        var merged = try Self.merge(snapshots[coordinate], daily: result.daily, timeZone: destinationZone, now: now)
        if useArchive { merged.fetched = snapshots[coordinate]?.fetched ?? .distantPast }
        snapshots[coordinate] = merged
        await disk.write(merged, at: coordinate)
        return merged.days[day]
    }

    private struct Response: Decodable { let daily: Daily; let timezone: String? }
    struct Daily: Decodable {
        let time: [String]
        let weather_code: [Int?]
        let temperature_2m_min: [Double?]
        let temperature_2m_max: [Double?]
        let precipitation_probability_max: [Int?]?

        func weather(on day: String) throws -> TripDayWeather? {
            guard [weather_code.count, temperature_2m_min.count, temperature_2m_max.count,
                   precipitation_probability_max?.count ?? time.count].allSatisfy({ $0 == time.count }) else {
                throw URLError(.cannotParseResponse)
            }
            guard let index = time.firstIndex(of: day) else { return nil }
            return TripDayWeather(date: day, weatherCode: weather_code[index],
                minimumCelsius: temperature_2m_min[index], maximumCelsius: temperature_2m_max[index],
                precipitationProbability: precipitation_probability_max?[index])
        }
    }
}

// Independent actor keeps all filesystem work off the UI actor.
private actor TripWeatherDiskCache {
    let directory: URL
    init(directory: URL?) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WeatherSnapshots", isDirectory: true)
    }
    private func file(_ coordinate: Coordinate) -> URL {
        let key = "\(coordinate.latitude)|\(coordinate.longitude)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
    func read(_ coordinate: Coordinate) -> TripWeatherService.Snapshot? {
        guard let data = try? Data(contentsOf: file(coordinate)) else { return nil }
        return try? JSONDecoder().decode(TripWeatherService.Snapshot.self, from: data)
    }
    func write(_ snapshot: TripWeatherService.Snapshot, at coordinate: Coordinate) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: file(coordinate), options: .atomic)
        } catch { /* Keep the in-memory forecast if local storage is unavailable. */ }
    }
}
