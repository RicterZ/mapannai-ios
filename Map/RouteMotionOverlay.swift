import UIKit

/// All providers share directional arrows, timing, layers and lifecycle.
/// The only SDK-specific operation is projecting a coordinate into the map view.
@MainActor final class RouteMotionOverlay: NSObject {
    private weak var host: UIView?
    private var geometry: [RouteOverlayGeometry] = []
    private var arrows: [CAShapeLayer] = []
    private let arrowContainer = CALayer()
    private let routeMask = CAShapeLayer()
    private var tracks: [(RouteMotionPath, Int)] = []
    private var screenPaths: [(RouteDirectionPath, Int)] = []
    private var projectionDirty = true
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var project: ((Coordinate) -> CGPoint)?
    private var enabled: (() -> Bool)?
    private(set) var isRunning = false
    private var suspended = false

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(resumeFromBackground), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(pauseForBackground), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }
    deinit { preparation?.cancel(); NotificationCenter.default.removeObserver(self) }

    func update(routes: [DisplayRoute], in view: UIView, enabled: @escaping () -> Bool,
                project: @escaping (Coordinate) -> CGPoint) {
        self.enabled = enabled; self.project = project
        let snapshot = routes.map(RouteOverlayGeometry.init)
        guard host !== view || geometry != snapshot else { refreshPlayback(invalidateProjection: false); return }
        stop(); host = view; geometry = snapshot
        arrowContainer.zPosition = 1000; arrowContainer.frame = view.bounds
        routeMask.fillColor = nil; routeMask.strokeColor = UIColor.black.cgColor
        routeMask.lineWidth = RouteLineAppearance.width(selected: true)
        routeMask.lineCap = .round; routeMask.lineJoin = .round
        arrowContainer.mask = routeMask
        if !snapshot.isEmpty { view.layer.addSublayer(arrowContainer) }
        let token = UUID(); generation = token
        preparation = Task { [weak self] in
            // Route metrics can be large. Never calculate them on the UI thread.
            let worker = Task.detached(priority: .userInitiated) {
                snapshot.compactMap { route -> (RouteMotionPath, Int)? in
                    guard !Task.isCancelled else { return nil }
                    let path = RouteMotionPath(points: route.points)
                    return path.length > 0 ? (path, route.colorIndex) : nil
                }
            }
            let tracks = await withTaskCancellationHandler(operation: { await worker.value }, onCancel: { worker.cancel() })
            guard let self, !Task.isCancelled, self.generation == token, let host = self.host else { return }
            self.tracks = tracks; self.projectionDirty = true
            self.preparation = nil; self.refresh()
        }
    }
    @objc func refresh() { refreshPlayback(invalidateProjection: true) }
    private func refreshPlayback(invalidateProjection: Bool) {
        if invalidateProjection { projectionDirty = true }
        let active = !suspended && UIApplication.shared.applicationState == .active
            && enabled?() == true && host?.window != nil && !tracks.isEmpty
        guard active else { pause(); return }
        isRunning = false
        render(timestamp: 0, reducedMotion: true)
    }
    @objc private func pauseForBackground() { suspended = true; pause() }
    @objc private func resumeFromBackground() { suspended = false; refresh() }
    private func pause() {
        isRunning = false
        CATransaction.begin(); CATransaction.setDisableActions(true)
        arrows.forEach { $0.isHidden = true }; CATransaction.commit()
    }
    func stop() {
        preparation?.cancel(); preparation = nil; generation = UUID()
        pause(); arrows.forEach { $0.removeFromSuperlayer() }; arrows = []; arrowContainer.removeFromSuperlayer(); tracks = []; screenPaths = []; geometry = []
    }
    private func render(timestamp: Double, reducedMotion: Bool) {
        guard let host, let project else { return }
        if projectionDirty {
            screenPaths = tracks.map { (RouteDirectionPath(points: $0.0.points.map(project), bounds: host.bounds), $0.1) }
            arrowContainer.frame = host.bounds
            let mask = UIBezierPath()
            for (path, _) in screenPaths {
                for (index, point) in path.points.enumerated() {
                    if index == 0 { mask.move(to: point) } else { mask.addLine(to: point) }
                }
            }
            CATransaction.begin(); CATransaction.setDisableActions(true)
            routeMask.path = mask.cgPath; CATransaction.commit()
            projectionDirty = false
        }
        let arrows = screenPaths.flatMap { path, color in
            path.arrows(timestamp: timestamp, reducedMotion: reducedMotion, bounds: host.bounds).map { ($0, color) }
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        while self.arrows.count < arrows.count {
            let arrow = CAShapeLayer()
            let shape = UIBezierPath(); shape.move(to: CGPoint(x: -2.5, y: -2.3)); shape.addLine(to: CGPoint(x: 1.5, y: 0)); shape.addLine(to: CGPoint(x: -2.5, y: 2.3))
            arrow.path = shape.cgPath; arrow.fillColor = nil
            arrow.strokeColor = UIColor.white.cgColor; arrow.lineWidth = 1.4
            arrow.lineCap = .round; arrow.lineJoin = .round; arrow.zPosition = 1000
            arrowContainer.addSublayer(arrow); self.arrows.append(arrow)
        }
        for (index, layer) in self.arrows.enumerated() {
            guard index < arrows.count else { layer.isHidden = true; continue }
            let (arrow, color) = arrows[index]
            layer.position = arrow.position; layer.setAffineTransform(CGAffineTransform(rotationAngle: arrow.angle))
            layer.opacity = arrow.opacity; layer.isHidden = false
            layer.shadowColor = UIColor(Theme.color(color)).cgColor; layer.shadowOpacity = 0; layer.shadowRadius = 1; layer.shadowOffset = .zero
        }
        CATransaction.commit()
    }
}
