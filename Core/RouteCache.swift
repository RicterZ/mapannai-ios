import Foundation
import CryptoKit

actor RouteCache {
    private struct Entry: Codable {
        var route: PlannedRoute
        var createdAt: Date
    }
    private var memory: [String: Entry] = [:]
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AMapRoutes", isDirectory: true)
    }
    nonisolated static func key(_ a: Coordinate, _ b: Coordinate, mode: TransportMode?, provider: MapServiceProvider = .amap, server: String = "") -> String {
        "server-route-v2|\(server)|\(provider.rawValue)|\(mode?.rawValue ?? "server-default")|\(a.latitude),\(a.longitude)|\(b.latitude),\(b.longitude)"
    }
    private func url(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
    func get(_ key: String, now: Date = Date()) -> PlannedRoute? {
        assert(!Thread.isMainThread, "Route cache reads must stay off the UI thread")
        let entry: Entry
        if let cached = memory[key] { entry = cached }
        else {
            guard let data = try? Data(contentsOf: url(key)), let cached = try? JSONDecoder().decode(Entry.self, from: data) else { return nil }
            entry = cached
        }
        let route = entry.route
        guard route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { return nil }
        let transit = ["bus", "subway", "train"].contains { key.contains("|\($0)|") }
        if transit && (!route.isFallback || route.fallback == "NO_ROUTE") && now.timeIntervalSince(entry.createdAt) >= 3600 {
            memory[key] = nil; return nil
        }
        memory[key] = entry; return route
    }
    func put(_ route: PlannedRoute, key: String) {
        assert(!Thread.isMainThread, "Route cache writes must stay off the UI thread")
        guard route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { return }
        let entry = Entry(route: route, createdAt: Date())
        memory[key] = entry
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(entry) { try? data.write(to: url(key), options: .atomic) }
    }
}
