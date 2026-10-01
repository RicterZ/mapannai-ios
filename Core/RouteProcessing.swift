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
                        display.points = old.points
                        display.isPlanned = true
                    }
                    segments.append(RouteSegment(display: display, origin: a.coordinates, destination: b.coordinates))
                }
            }
        }
        return segments
    }
    /// Hydrate every cached segment before exposing a new selection to the map.
    /// Previously hidden days must not pass through an unrelated fallback curve.
    func restoringCachedGeometry(_ segments: [RouteSegment], cache: RouteCache,
                                 mode: TravelMode, provider: MapServiceProvider, server: String) async throws -> [RouteSegment] {
        var restored = segments
        for index in restored.indices {
            try Task.checkCancellation()
            let segment = restored[index]
            if segment.display.isPlanned { continue }
            let key = RouteCache.key(segment.origin, segment.destination, mode: mode, provider: provider, server: server)
            guard let cached = await cache.get(key) else { continue }
            restored[index].display.points = try displayPoints(cached, origin: segment.origin, destination: segment.destination)
            restored[index].display.isPlanned = !cached.isFallback
        }
        try Task.checkCancellation()
        return restored
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
    func amapSnapshot(_ routes: [RouteOverlayGeometry]) throws -> [PreparedRouteOverlay] {
        var prepared: [PreparedRouteOverlay] = []
        for route in routes {
            try Task.checkCancellation()
            let coordinates = try amapCoordinates(route.points)
            prepared.append(PreparedRouteOverlay(geometry: route, coordinates: coordinates,
                hitIndex: try RouteSpatialIndex(points: coordinates)))
        }
        try Task.checkCancellation()
        return prepared
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
