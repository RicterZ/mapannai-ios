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
    private var visible = false
    private(set) var isRunning = false
    static let strokeWidth: CGFloat = 1.82
    static let strokeColor = UIColor.white
    static let glyphPoints = [CGPoint(x: -2, y: -1.8), CGPoint(x: 1, y: 0), CGPoint(x: -2, y: 1.8)]

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
        guard host != nil, let project, let unproject, let cameraKey, let publish else { return }
        guard enabled?() == true, !geometry.isEmpty else {
            if visible { publish([]) }
            visible = false; renderedKey = nil; return
        }
        let key = cameraKey()
        if visible, let renderedKey, abs(renderedKey - key) <= max(abs(key), 1) * 0.000001 { return }
        // Generate the complete route, not a viewport-dependent selection. The SDK clips
        // native geometry; camera translation and rotation never resubmit arrow vertices.
        let paths = geometry.flatMap { route -> [[Coordinate]] in
            let projected = route.points.map(project)
            let finite = projected.filter { $0.x.isFinite && $0.y.isFinite }
            guard let first = finite.first else { return [] }
            let extent = finite.dropFirst().reduce(CGRect(origin: first, size: .zero)) { rect, point in
                CGRect(x: min(rect.minX, point.x), y: min(rect.minY, point.y),
                       width: max(rect.maxX, point.x) - min(rect.minX, point.x),
                       height: max(rect.maxY, point.y) - min(rect.minY, point.y))
            }.insetBy(dx: -12, dy: -12)
            let path = RouteDirectionPath(points: finite, bounds: extent)
            return path.arrows(timestamp: 0, reducedMotion: true, bounds: extent).map { arrow in
                // Fits within the 6pt selected route, including the 1.82pt stroke.
                let cosine = cos(arrow.angle), sine = sin(arrow.angle)
                return Self.glyphPoints.map { point in
                    unproject(CGPoint(x: arrow.position.x + point.x * cosine - point.y * sine,
                                      y: arrow.position.y + point.x * sine + point.y * cosine))
                }
            }
        }
        renderedKey = key; visible = true; publish(paths)
    }
    func stop() {
        if visible { publish?([]) }
        visible = false; renderedKey = nil; geometry = []
    }
}
