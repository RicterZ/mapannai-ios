import UIKit

/// Observes SDK gestures without adding a competing recognizer.
/// A two-finger gesture remains a zoom/rotation until every recognizer ends.
@MainActor final class MapNavigationGestures: NSObject {
    private let recognizers = NSHashTable<UIGestureRecognizer>.weakObjects()
    private var policy = LocationGesturePolicy()
    var onTransformEnded: (() -> Void)?
    private var onPan: (() -> Void)?
    var isInteracting: Bool { recognizers.allObjects.contains { $0.state == .began || $0.state == .changed } }

    func observe(_ view: UIView, onPan: @escaping () -> Void) {
        self.onPan = onPan
        collect(view)
        classify()
    }
    private func collect(_ view: UIView) {
        for recognizer in view.gestureRecognizers ?? [] where recognizer is UIPanGestureRecognizer || recognizer is UIPinchGestureRecognizer || recognizer is UIRotationGestureRecognizer {
            if !recognizers.contains(recognizer) {
                recognizers.add(recognizer)
                recognizer.addTarget(self, action: #selector(changed))
            }
        }
        view.subviews.forEach(collect)
    }
    @objc private func changed() { classify() }
    private func classify() {
        let active = recognizers.allObjects.filter { $0.state == .began || $0.state == .changed }
        let transform = active.contains { $0.numberOfTouches > 1 || $0 is UIPinchGestureRecognizer || $0 is UIRotationGestureRecognizer }
        let distances = active.compactMap { recognizer -> Double? in
            guard let pan = recognizer as? UIPanGestureRecognizer, pan.state == .changed, pan.numberOfTouches == 1 else { return nil }
            let translation = pan.translation(in: pan.view)
            return Double(hypot(translation.x, translation.y))
        }
        switch policy.update(active: !active.isEmpty, transform: transform, singlePanDistance: distances.max()) {
        case .pan: onPan?()
        case .transformEnded: onTransformEnded?()
        case .none: break
        }
    }
}
