import Foundation

struct RouteSegment {
    var display: DisplayRoute
    var origin: Coordinate
    var destination: Coordinate
}

/// Pure value snapshots enter this actor; UIKit/SwiftUI and store mutations never do.
actor RouteProcessing {
    func build(days: [TripDay], markers: [Marker], selectedTrip: Trip?, previous: [DisplayRoute], preserve: Bool) throws -> [RouteSegment] {
        assert(!Thread.isMainThread, "Route building must stay off the UI thread")
        let lookup = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let oldRoutes = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        var segments: [RouteSegment] = []
        for day in days {
            try Task.checkCancellation()
            for (chainIndex, chain) in day.chains.enumerated() where chain.count > 1 {
                for i in 1..<chain.count {
                    try Task.checkCancellation()
                    guard let a = lookup[chain[i-1]], let b = lookup[chain[i]] else { continue }
                    var display = DisplayRoute(id: "\(day.id)|\(chainIndex)|\(i)|\(a.id)|\(b.id)",
                                               dayID: day.id, tripID: day.tripId,
                                               colorIndex: day.colorIndex ?? (selectedTrip?.days.firstIndex { $0.id == day.id } ?? 0),
                                               points: RouteGeometry.curve(a.coordinates, b.coordinates), isPlanned: false)
                    if preserve, let old = oldRoutes[display.id], old.isPlanned,
                       old.points.first == a.coordinates, old.points.last == b.coordinates {
                        display = old
                    }
                    segments.append(RouteSegment(display: display, origin: a.coordinates, destination: b.coordinates))
                }
            }
        }
        return segments
    }
    func displayPoints(_ route: PlannedRoute, origin: Coordinate, destination: Coordinate) throws -> [Coordinate] {
        assert(!Thread.isMainThread, "Route smoothing must stay off the UI thread")
        try Task.checkCancellation()
        if route.isFallback { return RouteGeometry.curve(origin, destination) }
        var points = route.path.map(\.coordinate)
        points.insert(origin, at: 0); points.append(destination)
        let result = RouteGeometry.smooth(points)
        try Task.checkCancellation()
        return result
    }
    func amapCoordinates(_ points: [Coordinate]) throws -> [Coordinate] {
        assert(!Thread.isMainThread, "Bulk coordinate conversion must stay off the UI thread")
        try Task.checkCancellation()
        var result: [Coordinate] = []; result.reserveCapacity(points.count)
        for (index, point) in points.enumerated() {
            if index.isMultiple(of: 256) { try Task.checkCancellation() }
            result.append(Coordinates.gcj(point))
        }
        return result
    }
}
