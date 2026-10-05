import Foundation

/// City/region overview uses dots and thin endpoint connections without route hit targets.
enum MapZoomPresentation {
    static func overviewCurve(_ route: DisplayRoute) -> [Coordinate] {
        guard let first = route.points.first, let last = route.points.last else { return [] }
        return RouteGeometry.curve(first, last)
    }
    static let compactThreshold = 10.0
    static let transitionDuration = 0.2
    static func isCompact(_ zoom: Double) -> Bool { zoom < compactThreshold }
}
