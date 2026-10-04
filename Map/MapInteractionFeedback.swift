import UIKit

@MainActor enum MapInteractionFeedback {
    static let duration = 0.22
    static func revealTarget(_ point: CGPoint, bounds: CGRect, insets: UIEdgeInsets) -> CGPoint {
        let visible = bounds.inset(by: insets).insetBy(dx: 22, dy: 44)
        return CGPoint(x: min(max(point.x, visible.minX), visible.maxX),
                       y: min(max(point.y, visible.minY), visible.maxY))
    }
    static func appear(_ view: UIView) {
        guard !UIAccessibility.isReduceMotionEnabled else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.75; scale.toValue = 1; scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
        view.layer.add(scale, forKey: "draft-appear-scale")
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0; fade.toValue = 1; fade.duration = duration
        view.layer.add(fade, forKey: "draft-appear-fade")
    }
    static func disappear(_ view: UIView?, completion: @escaping () -> Void) {
        guard let view, !UIAccessibility.isReduceMotionEnabled else { completion(); return }
        UIView.animate(withDuration: duration, animations: {
            view.alpha = 0; view.transform = CGAffineTransform(scaleX: 0.75, y: 0.75)
        }, completion: { _ in completion() })
    }
}

/// Wait for the SDK's POI callback before committing a line hit. A claimed
/// annotation or POI cancels the pending line, preventing two sheets flashing.
@MainActor final class MapTapArbiter {
    private var pending: DispatchWorkItem?
    private var claimedUntil = Date.distantPast
    func claim() { pending?.cancel(); pending = nil; claimedUntil = Date().addingTimeInterval(0.25) }
    func scheduleRoute(_ action: @escaping () -> Void) {
        pending?.cancel()
        guard Date() >= claimedUntil else { return }
        let work = DispatchWorkItem(block: action)
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
    func cancel() { pending?.cancel(); pending = nil }
}
