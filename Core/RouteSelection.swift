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
}

/// Progress is a segment and a fraction, not an elapsed-time percentage of the whole route.
/// Reprojecting that segment preserves the location on zoom while keeping travel at 60pt/s.
struct RouteMotionCursor {
    private var segment = 0
    private var fraction = 0.0
    mutating func advance(on path: RouteMotionPath, distance: Double,
                          project: (Coordinate) -> CGPoint) -> CGPoint? {
        guard let first = path.points.first else { return nil }
        guard path.points.count > 1 else { return project(first) }
        var remaining = max(0, distance)
        for _ in 0...(path.points.count * 2) {
            let a = project(path.points[segment]), b = project(path.points[segment + 1])
            let length = hypot(b.x - a.x, b.y - a.y)
            let available = Double(length) * (1 - fraction)
            if length > 0, remaining < available {
                fraction += remaining / Double(length)
                return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            }
            remaining = max(0, remaining - available)
            segment += 1; fraction = 0
            if segment == path.points.count - 1 {
                segment = 0
                // A tiny route may loop several times in one frame. Avoid repeatedly walking it.
                let total = zip(path.points, path.points.dropFirst()).reduce(0.0) { result, pair in
                    let a = project(pair.0), b = project(pair.1)
                    return result + Double(hypot(b.x - a.x, b.y - a.y))
                }
                guard total > 0 else { return project(first) }
                remaining = remaining.truncatingRemainder(dividingBy: total)
            }
        }
        return project(first)
    }
}

final class RouteMotionAnimation {
    static let pointsPerSecond = 60.0
    private var paths: [RouteMotionPath] = []
    private var cursors: [RouteMotionCursor] = []
    private var lastTimestamp: Double?
    func reset(paths: [RouteMotionPath] = []) {
        self.paths = paths
        cursors = paths.map { _ in RouteMotionCursor() }
        lastTimestamp = nil
    }
    func positions(timestamp: Double, project: (Coordinate) -> CGPoint) -> [CGPoint?] {
        // Don't catch up after suspension or a long UI stall with a sudden jump.
        let delta = min(0.1, max(0, timestamp - (lastTimestamp ?? timestamp)))
        lastTimestamp = timestamp
        return paths.indices.map { index in
            cursors[index].advance(on: paths[index], distance: Self.pointsPerSecond * delta, project: project)
        }
    }
}
