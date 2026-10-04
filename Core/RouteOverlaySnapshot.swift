import Foundation

/// Only drawable state participates in native overlay identity. Selection flags do not.
struct RouteOverlayGeometry: Equatable {
    let id: String
    let points: [Coordinate]
    let colorIndex: Int
    let isDashed: Bool

    init(_ route: DisplayRoute) {
        id = route.id; points = route.points; colorIndex = route.colorIndex; isDashed = route.isDashed
    }
}

struct PreparedRouteOverlay {
    let geometry: RouteOverlayGeometry
    let coordinates: [Coordinate]
    let hitIndex: RouteSpatialIndex
}
