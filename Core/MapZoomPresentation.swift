import Foundation

/// City/region overview keeps route geometry with thin lines and no route hit targets.
enum MapZoomPresentation {
    static func overviewCurve(_ route: DisplayRoute) -> [Coordinate] {
        route.points
    }
    static let compactThreshold = 10.0
    static let transitionDuration = 0.2
    static func isCompact(_ zoom: Double) -> Bool { zoom < compactThreshold }
}
