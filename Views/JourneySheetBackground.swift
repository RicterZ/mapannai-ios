import SwiftUI

/// One native material for every navigation page. Tint becomes opaque as the
/// system sheet grows, using its actual height rather than a detent switch.
struct JourneySheetBackground: View {
    let availableHeight: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let fullHeight = max(availableHeight, 1)
            let progress = min(1, max(0, (geometry.size.height / fullHeight - 0.55) / 0.35))
            Rectangle().fill(.regularMaterial)
                .overlay {
                    Color(uiColor: .systemGroupedBackground)
                        .opacity(0.18 + 0.82 * progress)
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: progress)
                .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}

/// Pushed pages otherwise get their own opaque navigation-host background.
struct JourneyNavigationBackground: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.containerBackground(.clear, for: .navigation)
        } else {
            content.background(Color.clear)
        }
    }
}
