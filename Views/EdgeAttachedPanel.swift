import SwiftUI
import UIKit

extension View {
    func edgeAttachedPanel<Panel: View>(isPresented: Binding<Bool>,
        detent: Binding<ItineraryDetent> = .constant(.half), compactHeight: CGFloat? = nil,
        canDismiss: Bool = true, dimsBackground: Bool = false, backgroundColor: UIColor = .systemGroupedBackground, animatesPresentation: Bool = true, topContentInset: CGFloat = 24, fullTopInset: CGFloat = 8, onHeightChange: @escaping (CGFloat) -> Void = { _ in }, onMotionChange: @escaping (Bool) -> Void = { _ in }, onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> Panel) -> some View {
        background(EdgePanelAdaptation(presented: isPresented, detent: detent, compactHeight: compactHeight,
            canDismiss: canDismiss, dimsBackground: dimsBackground, backgroundColor: backgroundColor, animatesPresentation: animatesPresentation, topContentInset: topContentInset, fullTopInset: fullTopInset, onHeightChange: onHeightChange, onMotionChange: onMotionChange, onDismiss: onDismiss,
            content: AnyView(content())))
    }
}

private struct EdgePanelAdaptation: View {
    @Binding var presented: Bool
    @Binding var detent: ItineraryDetent
    let compactHeight: CGFloat?
    let canDismiss: Bool
    let dimsBackground: Bool
    let backgroundColor: UIColor
    let animatesPresentation: Bool
    let topContentInset: CGFloat
    let fullTopInset: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onMotionChange: (Bool) -> Void
    let onDismiss: () -> Void
    let content: AnyView
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var body: some View {
        if horizontalSizeClass == .regular {
            Color.clear.sheet(isPresented: $presented, onDismiss: onDismiss) {
                content.presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
                    .interactiveDismissDisabled(!canDismiss)
            }
        } else {
            EdgePanelPresenter(presented: $presented, detent: $detent, compactHeight: compactHeight,
                canDismiss: canDismiss, dimsBackground: dimsBackground, backgroundColor: backgroundColor, animatesPresentation: animatesPresentation, topContentInset: topContentInset, fullTopInset: fullTopInset, onHeightChange: onHeightChange, onMotionChange: onMotionChange, onDismiss: onDismiss, content: content)
        }
    }
}

/// A custom presentation owns only the panel frame; SwiftUI owns navigation and keyboard-safe content.
private struct EdgePanelPresenter: UIViewControllerRepresentable {
    @Binding var presented: Bool
    @Binding var detent: ItineraryDetent
    let compactHeight: CGFloat?
    let canDismiss: Bool
    let dimsBackground: Bool
    let backgroundColor: UIColor
    let animatesPresentation: Bool
    let topContentInset: CGFloat
    let fullTopInset: CGFloat
    let onHeightChange: (CGFloat) -> Void
    let onMotionChange: (Bool) -> Void
    let onDismiss: () -> Void
    let content: AnyView
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.onAppear = { [weak coordinator = context.coordinator] in coordinator?.update() }
        context.coordinator.anchor = anchor
        return anchor
    }
    func updateUIViewController(_ controller: Anchor, context: Context) {
        context.coordinator.value = self
        context.coordinator.update()
    }
    static func dismantleUIViewController(_ controller: Anchor, coordinator: Coordinator) {
        coordinator.host?.dismiss(animated: false)
    }
    final class Anchor: UIViewController {
        var onAppear: (() -> Void)?
        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); onAppear?() }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if view.window != nil { onAppear?() }
        }
    }
    final class PanelHost: UIViewController {
        private let hosting: UIHostingController<AnyView>
        var rootView: AnyView {
            get { hosting.rootView }
            set { hosting.rootView = newValue }
        }
        init(rootView: AnyView) {
            hosting = UIHostingController(rootView: rootView)
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidLoad() {
            super.viewDidLoad()
            addChild(hosting)
            hosting.view.backgroundColor = .clear
            hosting.view.insetsLayoutMarginsFromSafeArea = false
            hosting.view.setContentHuggingPriority(.defaultLow, for: .vertical)
            hosting.view.frame = view.bounds
            hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(hosting.view)
            hosting.didMove(toParent: self)
        }
    }
    final class Coordinator: NSObject, UIViewControllerTransitioningDelegate {
        var value: EdgePanelPresenter
        weak var anchor: Anchor?
        var host: PanelHost?
        weak var panel: Presentation?
        var transitioning = false
        var lastRequestedDetent: ItineraryDetent?
        init(_ value: EdgePanelPresenter) {
            self.value = value
            super.init()
            NotificationCenter.default.addObserver(self, selector: #selector(retry), name: .edgePanelDismissed, object: nil)
        }
        deinit { NotificationCenter.default.removeObserver(self) }
        @objc private func retry() { update() }
        func update() {
            if let host {
                if value.presented {
                    host.rootView = value.content
                    let topInset = value.detent == .compact ? 0 : value.topContentInset
                    if host.additionalSafeAreaInsets.top != topInset {
                        host.additionalSafeAreaInsets.top = topInset
                        panel?.containerView?.setNeedsLayout()
                    }
                    if host.view.backgroundColor != value.backgroundColor {
                        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0 : 0.22) {
                            host.view.backgroundColor = self.value.backgroundColor
                            self.panel?.containerView?.setNeedsLayout()
                            self.panel?.containerView?.layoutIfNeeded()
                        }
                    }
                }
                if lastRequestedDetent != value.detent {
                    lastRequestedDetent = value.detent
                    host.additionalSafeAreaInsets.top = value.detent == .compact ? 0 : value.topContentInset
                    panel?.setDetent(value.detent, animated: true)
                }
                if !value.presented && !transitioning {
                    transitioning = true
                    value.onMotionChange(true)
                    host.dismiss(animated: !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                        guard let self else { return }
                        self.host = nil; self.panel = nil; self.transitioning = false
                        self.value.onDismiss()
                        NotificationCenter.default.post(name: .edgePanelDismissed, object: nil)
                    }
                }
                return
            }
            guard value.presented, !transitioning, let anchor, anchor.view.window != nil else { return }
            var presenter: UIViewController = anchor
            while let parent = presenter.parent { presenter = parent }
            // A sibling panel must finish dismissing before the next one presents.
            guard presenter.presentedViewController == nil else { return }
            let host = PanelHost(rootView: value.content)
            host.modalPresentationStyle = .custom
            host.transitioningDelegate = self
            host.view.backgroundColor = value.backgroundColor
            host.view.accessibilityIdentifier = "edge-attached-panel"
            host.view.accessibilityViewIsModal = value.dimsBackground
            host.additionalSafeAreaInsets.top = value.detent == .compact ? 0 : value.topContentInset
            self.host = host; lastRequestedDetent = value.detent; transitioning = true
            value.onMotionChange(true)
            presenter.present(host, animated: value.animatesPresentation && !UIAccessibility.isReduceMotionEnabled) { [weak self] in
                self?.transitioning = false
                self?.value.onMotionChange(false)
                self?.update()
            }
        }
        func presentationController(forPresented presented: UIViewController, presenting: UIViewController?, source: UIViewController) -> UIPresentationController? {
            let panel = Presentation(presentedViewController: presented, presenting: presenting)
            panel.coordinator = self; panel.detent = value.detent
            self.panel = panel
            return panel
        }
        func animationController(forPresented presented: UIViewController, presenting: UIViewController, source: UIViewController) -> UIViewControllerAnimatedTransitioning? { Slide(presenting: true) }
        func animationController(forDismissed dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? { Slide(presenting: false) }
        func close() { guard value.canDismiss else { return }; value.presented = false; update() }
    }
    final class Presentation: UIPresentationController, UIGestureRecognizerDelegate {
        weak var coordinator: Coordinator?
        var detent: ItineraryDetent = .half
        private var keyboardHeight: CGFloat = 0
        private var dragHeight: CGFloat?
        private var initialHeight: CGFloat = 0
        private var reportedHeight: CGFloat = 0
        private var verticalScroll: UIScrollView?
        private var draggingHeader = false
        private var pausedScrolls: [(scroll: UIScrollView, offset: CGPoint)] = []
        private let grabberArea = UIView()
        private let dimming = BackgroundTouchView()
        override var shouldRemovePresentersView: Bool { false }
        override var frameOfPresentedViewInContainerView: CGRect {
            guard let containerView else { return .zero }
            let bounds = containerView.bounds
            // Keep the panel behind the keyboard's rounded/translucent edges.
            // SwiftUI's keyboard safe area handles content avoidance inside it.
            let available = bounds.height
            let maximum = max(80, available - containerView.safeAreaInsets.top - (coordinator?.value.fullTopInset ?? 8))
            let height: CGFloat
            if keyboardHeight > 0 { height = maximum }
            else if let dragHeight {
                let minimum = coordinator?.value.compactHeight == nil && coordinator?.value.canDismiss == false
                    ? min(maximum, bounds.height * 0.5) : 40
                height = min(maximum, max(minimum, dragHeight))
            }
            else {
                switch detent {
                case .compact: height = coordinator?.value.compactHeight ?? 80
                case .half: height = min(maximum, bounds.height * 0.5)
                case .full: height = maximum
                }
            }
            return CGRect(x: 0, y: available - height, width: bounds.width, height: height)
        }
        override func presentationTransitionWillBegin() {
            guard let containerView, let presentedView else { return }
            dimming.frame = containerView.bounds
            dimming.backgroundColor = coordinator?.value.dimsBackground == true ? UIColor.black.withAlphaComponent(0.18) : .clear
            dimming.isUserInteractionEnabled = true
            if coordinator?.value.dimsBackground != true { dimming.targetView = presentingViewController.view }
            if coordinator?.value.dimsBackground == true { dimming.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(close))) }
            containerView.insertSubview(dimming, at: 0)
            presentedViewController.additionalSafeAreaInsets.top = detent == .compact ? 0 : (coordinator?.value.topContentInset ?? 24)
            presentedViewController.view.insetsLayoutMarginsFromSafeArea = false
            presentedView.layer.cornerRadius = 28
            presentedView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            presentedView.layer.cornerCurve = .continuous; presentedView.clipsToBounds = true
            grabberArea.backgroundColor = .clear
            grabberArea.accessibilityLabel = "面板高度"
            grabberArea.isAccessibilityElement = true
            grabberArea.accessibilityTraits = .button
            let line = UIView(frame: CGRect(x: 0, y: 8, width: 36, height: 5))
            line.backgroundColor = .tertiaryLabel; line.layer.cornerRadius = 2.5; line.tag = 1
            grabberArea.addSubview(line)
            let drag = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
            drag.delegate = self
            presentedView.addGestureRecognizer(drag)
            grabberArea.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(toggleHeight)))
            presentedView.addSubview(grabberArea)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(keyboard(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
        }
        override func dismissalTransitionDidEnd(_ completed: Bool) {
            if completed { restoreContentScrolling(); dimming.removeFromSuperview(); grabberArea.removeFromSuperview(); NotificationCenter.default.removeObserver(self) }
        }
        override func containerViewWillLayoutSubviews() {
            super.containerViewWillLayoutSubviews()
            presentedView?.frame = frameOfPresentedViewInContainerView
            let height = frameOfPresentedViewInContainerView.height
            if abs(height - reportedHeight) > 0.5 {
                reportedHeight = height
                let callback = coordinator?.value.onHeightChange
                DispatchQueue.main.async {
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { callback?(height) }
                }
            }
            dimming.frame = containerView?.bounds ?? .zero
            grabberArea.frame = CGRect(x: 0, y: 0, width: presentedView?.bounds.width ?? 0, height: min(24, coordinator?.value.topContentInset ?? 24))
            grabberArea.viewWithTag(1)?.center.x = grabberArea.bounds.midX
            grabberArea.isHidden = false
            grabberArea.accessibilityIdentifier = "edge-panel-grabber"
            presentedView?.layer.mask = nil
            presentedView?.bringSubviewToFront(grabberArea)
        }
        func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
            verticalScroll = nil
            draggingHeader = false
            guard let pan = gesture as? UIPanGestureRecognizer, let view = presentedView else { return true }
            let velocity = pan.velocity(in: view)
            guard abs(velocity.y) > abs(velocity.x) else { return false }
            let point = pan.location(in: view)
            // Header buttons retain their taps; the central header remains draggable.
            if point.y <= 96 {
                draggingHeader = point.y <= 24 || (point.x > 72 && point.x < view.bounds.width - 72)
                return draggingHeader
            }
            var target = view.hitTest(point, with: nil)
            while let current = target {
                if let scroll = current as? UIScrollView, scroll.contentSize.height > scroll.bounds.height {
                    if velocity.y > 0 && scroll.contentOffset.y <= -scroll.adjustedContentInset.top + 1 { verticalScroll = scroll; return true }
                    return false
                }
                target = current.superview
            }
            return false
        }
        func gestureRecognizer(_ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            other is UIPanGestureRecognizer
        }
        func setDetent(_ next: ItineraryDetent, animated: Bool) {
            guard next != detent else { return }
            detent = next; presentedViewController.additionalSafeAreaInsets.top = next == .compact ? 0 : (coordinator?.value.topContentInset ?? 24)
            layout(animated: animated)
        }
        private func layout(animated: Bool, duration: Double = 0.28, velocity: CGFloat = 0) {
            guard let containerView else { return }
            containerView.setNeedsLayout()
            if animated && !UIAccessibility.isReduceMotionEnabled {
                coordinator?.value.onMotionChange(true)
                UIView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: min(8, max(0, velocity)), options: [.beginFromCurrentState, .allowUserInteraction], animations: {
                    containerView.layoutIfNeeded()
                }, completion: { [weak self] finished in
                    if finished { self?.coordinator?.value.onMotionChange(false) }
                })
            } else {
                containerView.layoutIfNeeded()
                if dragHeight == nil { coordinator?.value.onMotionChange(false) }
            }
        }
        @objc private func toggleHeight() {
            let next: ItineraryDetent = detent == .full || detent == .compact ? .half : .full
            coordinator?.value.detent = next
            setDetent(next, animated: true)
        }
        @objc private func close() { coordinator?.close() }
        private func pauseContentScrolling(in view: UIView) {
            if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
               !scroll.isPagingEnabled, scroll.contentSize.height > scroll.bounds.height {
                pausedScrolls.append((scroll, scroll.contentOffset))
                // Cancel the content pan so movement is applied only to the panel.
                scroll.isScrollEnabled = false
            }
            for child in view.subviews { pauseContentScrolling(in: child) }
        }
        private func restoreContentScrolling() {
            for (scroll, offset) in pausedScrolls {
                scroll.setContentOffset(offset, animated: false)
                scroll.isScrollEnabled = true
            }
            pausedScrolls = []
        }
        @objc private func pan(_ gesture: UIPanGestureRecognizer) {
            guard keyboardHeight == 0 else { restoreContentScrolling(); return }
            switch gesture.state {
            case .began:
                if draggingHeader, let view = presentedView { pauseContentScrolling(in: view) }
                else if let scroll = verticalScroll {
                    pausedScrolls.append((scroll, CGPoint(x: scroll.contentOffset.x, y: -scroll.adjustedContentInset.top)))
                    scroll.isScrollEnabled = false
                }
                coordinator?.value.onMotionChange(true)
                if let current = presentedView?.layer.presentation()?.frame {
                    presentedView?.layer.removeAllAnimations(); presentedView?.frame = current
                }
                initialHeight = presentedView?.frame.height ?? frameOfPresentedViewInContainerView.height
            case .changed:
                dragHeight = initialHeight - gesture.translation(in: containerView).y
                layout(animated: false)
                for (scroll, offset) in pausedScrolls { scroll.setContentOffset(offset, animated: false) }
            case .ended, .cancelled:
                restoreContentScrolling()
                verticalScroll = nil
                let projected = (dragHeight ?? initialHeight) - gesture.velocity(in: containerView).y * 0.15
                dragHeight = nil
                if coordinator?.value.canDismiss == true && projected < initialHeight * 0.55 { close(); return }
                let full = (containerView?.bounds.height ?? 0) - (containerView?.safeAreaInsets.top ?? 0) - (coordinator?.value.fullTopInset ?? 8)
                var options: [(ItineraryDetent, CGFloat)] = [(.half, (containerView?.bounds.height ?? 0) * 0.5), (.full, full)]
                if let compact = coordinator?.value.compactHeight { options.insert((.compact, compact), at: 0) }
                let next = options.min { abs($0.1 - projected) < abs($1.1 - projected) }!.0
                detent = next; coordinator?.value.detent = next
                presentedViewController.additionalSafeAreaInsets.top = next == .compact ? 0 : (coordinator?.value.topContentInset ?? 24)
                let distance = abs(frameOfPresentedViewInContainerView.height - (presentedView?.frame.height ?? initialHeight))
                layout(animated: true, velocity: abs(gesture.velocity(in: containerView).y) / max(1, distance))
            default: break
            }
        }
        @objc private func keyboard(_ notification: Notification) {
            guard let containerView, let window = containerView.window,
                  let screenFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            let frame = containerView.convert(window.convert(screenFrame, from: nil), from: window)
            keyboardHeight = notification.name == UIResponder.keyboardWillHideNotification ? 0 : containerView.bounds.intersection(frame).height
            layout(animated: true, duration: notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double ?? 0.25)
        }
    }
    final class BackgroundTouchView: UIView {
        weak var targetView: UIView?
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if let targetView {
                return targetView.hitTest(convert(point, to: targetView), with: event)
            }
            return super.hitTest(point, with: event)
        }
    }
    final class Slide: NSObject, UIViewControllerAnimatedTransitioning {
        let presenting: Bool
        init(presenting: Bool) { self.presenting = presenting }
        func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval { UIAccessibility.isReduceMotionEnabled ? 0 : 0.28 }
        func animateTransition(using context: UIViewControllerContextTransitioning) {
            let key: UITransitionContextViewControllerKey = presenting ? .to : .from
            guard let controller = context.viewController(forKey: key), let view = context.view(forKey: presenting ? .to : .from) else { context.completeTransition(false); return }
            if presenting { context.containerView.addSubview(view); view.frame = context.finalFrame(for: controller) }
            let offscreen = CGAffineTransform(translationX: 0, y: context.containerView.bounds.maxY - view.frame.minY)
            if presenting { view.transform = offscreen }
            UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
                view.transform = self.presenting ? .identity : offscreen
            } completion: { _ in context.completeTransition(!context.transitionWasCancelled) }
        }
    }
}
private extension Notification.Name { static let edgePanelDismissed = Notification.Name("MapAnNai.edgePanelDismissed") }
