import SwiftUI

/// Animation choices by interaction, rather than a timing override on a whole screen.
/// Native navigation, sheets and map camera movement retain their own motion owners.
enum AppMotion {
    static func navigation(reduceMotion: Bool) -> Animation? { reduceMotion ? nil : .default }
    static func presentation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.35)
    }
    static func crossfade(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }
    static func disclosure(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.25)
    }
    static func scroll(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .smooth(duration: 0.3)
    }
    static func listMutation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.22)
    }

    static func workspaceTransition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

/// The sheet owns height interpolation. Content follows that height directly,
/// including when a drag reverses, without starting another timed animation.
enum JourneyPresentation {
    static let compactHeight: CGFloat = 80
    static func visibleHeight(layoutHeight: CGFloat, layoutTop: CGFloat, presentedTop: CGFloat) -> CGFloat {
        max(0, layoutHeight + layoutTop - presentedTop)
    }

    static func expandedProgress(height: CGFloat, compactHeight: CGFloat) -> Double {
        let span = max(compactHeight, 1)
        return Double(min(1, max(0, (height - compactHeight) / span)))
    }
}
