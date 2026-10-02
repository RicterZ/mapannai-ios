import SwiftUI
import UIKit

struct SheetPresentationGeometry {
    let layoutHeight: CGFloat
    let visibleHeight: CGFloat
    let safeAreaInsets: EdgeInsets
}

/// UISheetPresentationController can commit its destination bounds before its
/// settling animation finishes. Keep that layout separate from the on-screen
/// height, without supplying another animation curve or changing the sheet.
struct NativeSheetHeightReader<Content: View>: View {
    let enabled: Bool
    @ViewBuilder var content: (SheetPresentationGeometry) -> Content
    @State private var visibleHeight: CGFloat?

    var body: some View {
        GeometryReader { geometry in
            content(SheetPresentationGeometry(layoutHeight: geometry.size.height,
                visibleHeight: enabled ? (visibleHeight ?? geometry.size.height) : geometry.size.height,
                safeAreaInsets: geometry.safeAreaInsets))
                .background {
                    if enabled {
                        SheetHeightProbe(layoutHeight: geometry.size.height) { height in
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { visibleHeight = height }
                        }
                    }
                }
        }
    }
}

private struct SheetHeightProbe: UIViewRepresentable {
    let layoutHeight: CGFloat
    let onHeight: (CGFloat) -> Void

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.isAccessibilityElement = false
        return probe
    }
    func updateUIView(_ probe: Probe, context: Context) {
        probe.onHeight = onHeight
        if probe.layoutHeight != layoutHeight {
            probe.layoutHeight = layoutHeight
            probe.observeSettlement()
        }
    }
    static func dismantleUIView(_ probe: Probe, coordinator: ()) { probe.stop() }

    final class Probe: UIView {
        private final class TickTarget: NSObject {
            weak var probe: Probe?
            @objc func tick(_ link: CADisplayLink) { probe?.sample(link) }
        }
        var layoutHeight: CGFloat = 0
        var onHeight: ((CGFloat) -> Void)?
        private var displayLink: CADisplayLink?
        private let target = TickTarget()
        private var lastHeight: CGFloat?
        private var lastLayoutTime: CFTimeInterval = 0
        private var stableFrames = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { stop() } else { observeSettlement() }
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            observeSettlement()
        }
        func observeSettlement() {
            lastLayoutTime = CACurrentMediaTime()
            stableFrames = 0
            guard window != nil, displayLink == nil else { return }
            target.probe = self
            let link = CADisplayLink(target: target, selector: #selector(TickTarget.tick(_:)))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 120, preferred: 120)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        private func sample(_ link: CADisplayLink) {
            guard let window else { stop(); return }
            let layoutTop = layer.convert(.zero, to: window.layer).y
            let presentedTop = layer.presentation()?.convert(.zero,
                to: window.layer.presentation() ?? window.layer).y ?? layoutTop
            let height = JourneyPresentation.visibleHeight(layoutHeight: layoutHeight,
                layoutTop: layoutTop, presentedTop: presentedTop)
            if lastHeight == nil || abs(height - lastHeight!) > 0.25 {
                lastHeight = height
                stableFrames = 0
                onHeight?(height)
            } else {
                stableFrames += 1
            }
            // No idle display link. A new layout or drag starts observation again.
            if stableFrames >= 3 && link.timestamp - lastLayoutTime > 0.25 {
                // Finish on the exact resting height; do not retain a subpixel fade.
                if abs(height - layoutHeight) < 0.5, lastHeight != layoutHeight {
                    lastHeight = layoutHeight
                    onHeight?(layoutHeight)
                }
                stop()
            }
        }
        func stop() { displayLink?.invalidate(); displayLink = nil }
        deinit { displayLink?.invalidate() }
    }
}
