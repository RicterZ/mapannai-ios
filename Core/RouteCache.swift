import Foundation
import CryptoKit

actor RouteCache {
    private var memory: [String: PlannedRoute] = [:]
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("AMapRoutes", isDirectory: true)
    }
    nonisolated static func key(_ a: Coordinate, _ b: Coordinate, mode: TravelMode, provider: MapServiceProvider = .amap, server: String = "") -> String {
        "server-route-v1|\(server)|\(provider.rawValue)|\(mode.resolved(from: a, to: b).rawValue)|\(a.latitude),\(a.longitude)|\(b.latitude),\(b.longitude)"
    }
    private func url(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash).appendingPathExtension("json")
    }
    func get(_ key: String) -> PlannedRoute? {
        assert(!Thread.isMainThread, "Route cache reads must stay off the UI thread")
        if let route = memory[key] { return route }
        guard let data = try? Data(contentsOf: url(key)), let route = try? JSONDecoder().decode(PlannedRoute.self, from: data),
              route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { return nil }
        memory[key] = route; return route
    }
    func put(_ route: PlannedRoute, key: String) {
        assert(!Thread.isMainThread, "Route cache writes must stay off the UI thread")
        guard route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { return }
        memory[key] = route
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(route) { try? data.write(to: url(key), options: .atomic) }
    }
}
