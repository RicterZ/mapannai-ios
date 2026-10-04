import UIKit

/// Shared arrow geometry. Adapters only submit geographic polylines to their SDK.
/// There are no screen-space layers or camera-following transforms.
@MainActor final class RouteMotionOverlay: NSObject {
    private weak var host: UIView?
    private var geometry: [RouteOverlayGeometry] = []
    private var project: ((Coordinate) -> CGPoint)?
    private var unproject: ((CGPoint) -> Coordinate)?
    private var publish: (([[Coordinate]]) -> Void)?
    private var enabled: (() -> Bool)?
    private var cameraKey: (() -> Double)?
    private var renderedKey: Double?
    private var coverage = CGRect.zero
    private var anchor: (Coordinate, CGPoint)?
    private var visible = false
    private(set) var isRunning = false
    static let strokeWidth: CGFloat = 1.4
    static let strokeColor = UIColor.white

    func update(routes: [DisplayRoute], in view: UIView, enabled: @escaping () -> Bool,
                project: @escaping (Coordinate) -> CGPoint,
                unproject: @escaping (CGPoint) -> Coordinate,
                cameraKey: @escaping () -> Double,
                publish: @escaping ([[Coordinate]]) -> Void) {
        let snapshot = routes.map(RouteOverlayGeometry.init)
        if host !== view || geometry != snapshot { renderedKey = nil }
        host = view; geometry = snapshot; self.enabled = enabled
        self.project = project; self.unproject = unproject; self.cameraKey = cameraKey; self.publish = publish
        refresh()
    }
    @objc func refresh() {
        guard let host, let project, let unproject, let cameraKey, let publish else { return }
        guard enabled?() == true, !geometry.isEmpty else {
            if visible { publish([]) }
            visible = false; renderedKey = nil; return
        }
        let key = cameraKey()
        if visible, let renderedKey, abs(renderedKey - key) <= max(abs(key), 1) * 0.000001, let anchor {
            let current = project(anchor.0)
            let viewport = host.bounds.offsetBy(dx: anchor.1.x - current.x, dy: anchor.1.y - current.y)
            // Pan leaves native geographic overlays untouched; the SDK moves them with the route.
            if coverage.contains(viewport) { return }
        }
        coverage = host.bounds.insetBy(dx: -host.bounds.width, dy: -host.bounds.height)
        if let first = geometry.first?.points.first { anchor = (first, project(first)) }
        let paths = geometry.flatMap { route -> [[Coordinate]] in
            let path = RouteDirectionPath(points: route.points.map(project), bounds: coverage)
            return path.arrows(timestamp: 0, reducedMotion: true, bounds: coverage).map { arrow in
                // Fits within the 6pt selected route, including the 1.4pt stroke.
                let cosine = cos(arrow.angle), sine = sin(arrow.angle)
                return [CGPoint(x: -2, y: -1.8), CGPoint(x: 1, y: 0), CGPoint(x: -2, y: 1.8)].map { point in
                    unproject(CGPoint(x: arrow.position.x + point.x * cosine - point.y * sine,
                                      y: arrow.position.y + point.x * sine + point.y * cosine))
                }
            }
        }
        renderedKey = key; visible = true; publish(paths)
    }
    func stop() {
        if visible { publish?([]) }
        visible = false; renderedKey = nil; geometry = []; anchor = nil
    }
}
