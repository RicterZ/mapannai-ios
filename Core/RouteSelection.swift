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
    /// DisplayRoute is one directed edge between adjacent visits, never a whole chain.
    static func paths(_ routes: [DisplayRoute]) -> [RouteMotionPath] {
        routes.map { RouteMotionPath(points: $0.points) }
    }
}

struct RouteMotionPath {
    let points: [Coordinate]
    private let cumulative: [Double]
    let length: Double
    init(points: [Coordinate]) {
        var unique: [Coordinate] = [], distances: [Double] = []
        var total = 0.0
        for point in points where unique.last != point {
            if let previous = unique.last {
                let latitude = (point.latitude + previous.latitude) * .pi / 360
                let longitude = RouteGeoBounds.longitudeDelta(point.longitude - previous.longitude)
                total += hypot((point.latitude - previous.latitude) * 111_000,
                               longitude * 111_000 * cos(latitude))
            }
            unique.append(point); distances.append(total)
        }
        self.points = unique; cumulative = distances; length = total
    }
    /// Same cumulative-distance interpolation as Web pointAlongPath; O(log n) per dot.
    func coordinate(progress: Double) -> Coordinate? {
        guard let first = points.first else { return nil }
        guard length > 0, points.count > 1 else { return first }
        let distance = min(1, max(0, progress)) * length
        var low = 1, high = points.count - 1
        while low < high {
            let middle = (low + high) / 2
            if cumulative[middle] < distance { low = middle + 1 } else { high = middle }
        }
        let index = low - 1, segment = cumulative[low] - cumulative[index]
        let fraction = segment > 0 ? (distance - cumulative[index]) / segment : 0
        return Coordinate(latitude: points[index].latitude + (points[low].latitude - points[index].latitude) * fraction,
                          longitude: points[index].longitude + RouteGeoBounds.longitudeDelta(points[low].longitude - points[index].longitude) * fraction)
    }
}

final class RouteMotionAnimation {
    static let duration = 2.1
    private var paths: [RouteMotionPath] = []
    func reset(paths: [RouteMotionPath] = []) { self.paths = paths }
    static func progress(timestamp: Double) -> Double {
        max(0, timestamp).truncatingRemainder(dividingBy: duration) / duration
    }
    static func opacity(timestamp: Double) -> Float {
        let p = progress(timestamp: timestamp)
        return Float(min(1, p * 10, (1 - p) * 10))
    }
    func positions(timestamp: Double, project: (Coordinate) -> CGPoint) -> [CGPoint?] {
        let progress = Self.progress(timestamp: timestamp)
        return paths.map { $0.coordinate(progress: progress).map(project) }
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
