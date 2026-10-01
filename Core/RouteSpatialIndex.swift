import Foundation

/// Geographic broad phase only. Final hit distances still use the SDK's exact screen projection.
struct RouteGeoBounds {
    var west: Double
    var south: Double
    var east: Double
    var north: Double
    init(points: [Coordinate], referenceLongitude: Double) {
        let xs = points.map { referenceLongitude + Self.longitudeDelta($0.longitude - referenceLongitude) }
        west = xs.min() ?? referenceLongitude; east = xs.max() ?? referenceLongitude
        south = points.map(\.latitude).min() ?? 0; north = points.map(\.latitude).max() ?? 0
    }
    static func longitudeDelta(_ value: Double) -> Double {
        value - 360 * floor((value + 180) / 360)
    }
    func intersects(_ other: Self) -> Bool {
        west <= other.east && east >= other.west && south <= other.north && north >= other.south
    }
    func contains(_ other: Self) -> Bool {
        west <= other.west && east >= other.east && south <= other.south && north >= other.north
    }
    func shifted(_ longitude: Double) -> Self {
        var copy = self; copy.west += longitude; copy.east += longitude; return copy
    }
    func expanded(factor: Double) -> Self {
        var copy = self
        let x = (east - west) * factor, y = (north - south) * factor
        copy.west -= x; copy.east += x
        copy.south = max(-85, south - y); copy.north = min(85, north + y)
        return copy
    }
    var corners: [Coordinate] {
        [(west, south), (east, south), (east, north), (west, north)].map {
            Coordinate(latitude: $0.1, longitude: Self.longitudeDelta($0.0))
        }
    }
    func union(_ other: Self) -> Self {
        var copy = self
        copy.west = min(west, other.west); copy.east = max(east, other.east)
        copy.south = min(south, other.south); copy.north = max(north, other.north)
        return copy
    }
}

/// Immutable tree built by RouteProcessing alongside the coordinates used by the renderer.
/// Panning/zooming never rebuilds or destroys this index.
struct RouteSpatialIndex {
    private struct Segment {
        let a: Coordinate
        let b: Coordinate
        let bounds: RouteGeoBounds
    }
    private struct Node {
        let bounds: RouteGeoBounds
        let range: Range<Int>
        var left: Int? = nil
        var right: Int? = nil
    }
    private var segments: [Segment] = []
    private var nodes: [Node] = []
    init(points: [Coordinate]) throws {
        segments.reserveCapacity(max(0, points.count - 1))
        for index in 1..<max(1, points.count) {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            let a = points[index - 1], b = points[index]
            guard a.isValid, b.isValid else { continue }
            segments.append(Segment(a: a, b: b, bounds: RouteGeoBounds(points: [a, b], referenceLongitude: a.longitude)))
        }
        if !segments.isEmpty { _ = try build(0..<segments.count) }
    }
    private mutating func build(_ range: Range<Int>) throws -> Int {
        try Task.checkCancellation()
        let bounds = segments[range].dropFirst().reduce(segments[range.lowerBound].bounds) { $0.union($1.bounds) }
        let index = nodes.count
        nodes.append(Node(bounds: bounds, range: range))
        if range.count > 16 {
            let horizontal = bounds.east - bounds.west >= bounds.north - bounds.south
            segments[range].sort {
                horizontal ? $0.bounds.west + $0.bounds.east < $1.bounds.west + $1.bounds.east
                    : $0.bounds.south + $0.bounds.north < $1.bounds.south + $1.bounds.north
            }
            let middle = range.lowerBound + range.count / 2
            let left = try build(range.lowerBound..<middle)
            let right = try build(middle..<range.upperBound)
            nodes[index].left = left; nodes[index].right = right
        }
        return index
    }
    func nearestDistance(at tap: CGPoint, bounds: RouteGeoBounds,
                         project: (Coordinate) -> CGPoint) -> Double {
        guard !nodes.isEmpty else { return .infinity }
        var nearest = Double.infinity
        var visited: Set<Int> = []
        // The inverse viewport may straddle the date line. Test adjacent world copies.
        for offset in [-360.0, 0, 360.0] {
            let query = bounds.shifted(offset)
            var pending = [0]
            while let index = pending.popLast() {
                let node = nodes[index]
                guard node.bounds.intersects(query) else { continue }
                if let left = node.left, let right = node.right {
                    pending.append(left); pending.append(right)
                } else {
                    for i in node.range where segments[i].bounds.intersects(query) && visited.insert(i).inserted {
                        let a = project(segments[i].a), b = project(segments[i].b)
                        let dx = b.x - a.x, dy = b.y - a.y
                        let length = dx*dx + dy*dy
                        let t = length > 0 ? min(1, max(0, ((tap.x-a.x)*dx + (tap.y-a.y)*dy)/length)) : 0
                        nearest = min(nearest, hypot(tap.x-a.x-t*dx, tap.y-a.y-t*dy))
                    }
                }
            }
        }
        return nearest
    }
}
