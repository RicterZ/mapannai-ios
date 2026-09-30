import Foundation

/// City/region overview uses dots and hides both visible routes and their hit targets.
enum MapZoomPresentation {
    static let compactThreshold = 10.0
    static let transitionDuration = 0.2
    static func isCompact(_ zoom: Double) -> Bool { zoom < compactThreshold }
}
