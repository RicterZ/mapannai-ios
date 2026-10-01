import Foundation

/// Only drawable state participates in native overlay identity. Selection flags do not.
struct RouteOverlayGeometry: Equatable {
    let id: String
    let points: [Coordinate]
    let colorIndex: Int

    init(_ route: DisplayRoute) {
        id = route.id; points = route.points; colorIndex = route.colorIndex
    }
}

struct PreparedRouteOverlay {
    let geometry: RouteOverlayGeometry
    let coordinates: [Coordinate]
    let hitIndex: RouteSpatialIndex
}
