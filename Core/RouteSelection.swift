import Foundation

enum RouteSelection {
    static func candidates(at tap: (Double, Double), routes: [DisplayRoute],
                           project: (Coordinate) -> (Double, Double)) -> [DisplayRoute] {
        let hits = routes.map { ($0, RouteGeometry.nearestDistance(tap, to: $0.points.map(project))) }
            .filter { $0.1 <= 18 }.sorted { $0.1 < $1.1 }
        guard let nearest = hits.first?.1 else { return [] }
        let near = hits.filter { $0.1 <= nearest + 2 }
        var seen: Set<String> = []
        return near.compactMap { seen.insert($0.0.tripID + "|" + $0.0.dayID).inserted ? $0.0 : nil }
    }
    static func length(_ route: DisplayRoute) -> Double {
        zip(route.points, route.points.dropFirst()).reduce(0) { $0 + Coordinates.distance($1.0, $1.1) }
    }
    /// Independent chains never get an artificial link between their endpoints.
    static func paths(_ routes: [DisplayRoute]) -> [RouteMotionPath] {
        var keys: [String] = [], groups: [String: [Coordinate]] = [:]
        for route in routes {
            let key = route.id.split(separator: "|").prefix(2).joined(separator: "|")
            if groups[key] == nil { keys.append(key); groups[key] = [] }
            groups[key, default: []] += route.points
        }
        return keys.map { RouteMotionPath(points: groups[$0] ?? []) }
    }
}

struct RouteMotionPath {
    let points: [Coordinate]
    private let cumulative: [Double]
    private let total: Double
    init(points: [Coordinate]) {
        self.points = points
        var cumulative: [Double] = points.isEmpty ? [] : [0]
        for (a, b) in zip(points, points.dropFirst()) {
            cumulative.append((cumulative.last ?? 0) + Coordinates.distance(a, b))
        }
        self.cumulative = cumulative; total = cumulative.last ?? 0
    }
    func position(progress: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        guard total > 0 else { return first }
        let target = min(1, max(0, progress)) * total
        var lo = 1, hi = cumulative.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if cumulative[mid] < target { lo = mid + 1 } else { hi = mid }
        }
        let length = cumulative[lo] - cumulative[lo - 1]
        let t = length > 0 ? (target - cumulative[lo - 1]) / length : 0
        let a = points[lo - 1], b = points[lo]
        return Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * t,
                          longitude: a.longitude + (b.longitude - a.longitude) * t)
    }
    static func phase(elapsed: Double) -> Double {
        max(0, elapsed).truncatingRemainder(dividingBy: 2.4) / 2.4
    }
}
