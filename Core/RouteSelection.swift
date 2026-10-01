import Foundation

enum RouteSelection {
    static let hitRadius = 28.0
    static func candidates(at tap: (Double, Double), routes: [DisplayRoute],
                           project: (Coordinate) -> (Double, Double)) -> [DisplayRoute] {
        RouteHitIndex(routes: routes, project: project).candidates(at: tap)
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
    init(points: [Coordinate]) {
        // Duplicate vertices have no visible length and must not be walked every frame.
        var unique: [Coordinate] = []
        unique.reserveCapacity(points.count)
        for point in points where unique.last != point { unique.append(point) }
        self.points = unique
    }
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
        var measuringCycle = segment == 0 && fraction == 0
        var cycleLength = 0.0
        // At most: initial partial loop, one measured loop, final partial loop.
        for _ in 0...(path.points.count * 3) {
            let a = project(path.points[segment]), b = project(path.points[segment + 1])
            let length = hypot(b.x - a.x, b.y - a.y)
            let available = Double(length) * (1 - fraction)
            if length > 0, remaining < available {
                fraction += remaining / Double(length)
                return CGPoint(x: a.x + (b.x - a.x) * fraction, y: a.y + (b.y - a.y) * fraction)
            }
            remaining = max(0, remaining - available)
            if measuringCycle { cycleLength += Double(length) }
            segment += 1; fraction = 0
            if segment == path.points.count - 1 {
                segment = 0
                // Accumulate a whole cycle only if this frame actually traverses it.
                // Crossing the endpoint no longer projects the entire path a second time.
                if measuringCycle {
                    guard cycleLength > 0 else { return project(first) }
                    remaining = remaining.truncatingRemainder(dividingBy: cycleLength)
                } else { measuringCycle = true }
                cycleLength = 0
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

/// Built when displayed geometry or the map projection changes, never for an unchanged tap.
/// Segment bounds reject distant paths before computing the exact distance.
struct RouteHitIndex {
    private struct Segment {
        let a: (Double, Double)
        let b: (Double, Double)
        func distance(to p: (Double, Double)) -> Double? {
            let r = RouteSelection.hitRadius
            guard p.0 >= min(a.0, b.0) - r, p.0 <= max(a.0, b.0) + r,
                  p.1 >= min(a.1, b.1) - r, p.1 <= max(a.1, b.1) + r else { return nil }
            let dx = b.0 - a.0, dy = b.1 - a.1
            let length = dx * dx + dy * dy
            let t = length > 0 ? min(1, max(0, ((p.0-a.0)*dx + (p.1-a.1)*dy) / length)) : 0
            return hypot(p.0 - a.0 - t*dx, p.1 - a.1 - t*dy)
        }
    }
    private var entries: [(DisplayRoute, [Segment])] = []
    init(routes: [DisplayRoute], project: (Coordinate) -> (Double, Double)) {
        entries = routes.map { route in
            let points = route.points.map(project)
            return (route, zip(points, points.dropFirst()).map { Segment(a: $0, b: $1) })
        }
    }
    func candidates(at tap: (Double, Double)) -> [DisplayRoute] {
        var hits: [(DisplayRoute, Double)] = []
        for (route, segments) in entries {
            var nearest = Double.infinity
            for segment in segments {
                if let distance = segment.distance(to: tap) { nearest = min(nearest, distance) }
            }
            if nearest <= RouteSelection.hitRadius { hits.append((route, nearest)) }
        }
        hits.sort { $0.1 == $1.1 ? $0.0.id < $1.0.id : $0.1 < $1.1 }
        guard let nearest = hits.first?.1 else { return [] }
        var seen: Set<String> = []
        return hits.filter { $0.1 <= nearest + 2 }.compactMap {
            seen.insert($0.0.tripID + "|" + $0.0.dayID).inserted ? $0.0 : nil
        }
    }
}
