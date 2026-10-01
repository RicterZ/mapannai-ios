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
    /// One ordered sweep for the whole day, rather than restarting on every segment.
    static func progress(_ progress: Double, route: DisplayRoute, routes: [DisplayRoute]) -> Double {
        let lengths = routes.map { max(1, length($0)) }
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return 0 }
        let traveled = min(1, max(0, progress)) * lengths.reduce(0, +)
        return min(1, max(0, (traveled - lengths.prefix(index).reduce(0, +)) / lengths[index]))
    }
}
