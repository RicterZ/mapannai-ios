import SwiftUI

/// Compact glass follows the native sheet outline; expanded pages keep their
/// opaque grouped surface. Both follow the actual sheet height during a drag.
struct JourneySheetBackground: View {
    let availableHeight: CGFloat
    var usesCompactGlass = true

    var body: some View {
        NativeSheetHeightReader(enabled: true) { geometry in
            let fullHeight = max(availableHeight, 1)
            let progress = min(1, max(0, (geometry.visibleHeight / fullHeight - 0.55) / 0.35))
            let expansion = JourneyPresentation.expandedProgress(height: geometry.visibleHeight,
                compactHeight: JourneyPresentation.compactHeight)
            ZStack {
                if usesCompactGlass {
                    compactSurface
                        .opacity(1 - expansion)
                }
                Rectangle().fill(.regularMaterial)
                .overlay {
                    Color(uiColor: .systemGroupedBackground)
                        .opacity(0.18 + 0.82 * progress)
                }
                .ignoresSafeArea()
                .opacity(usesCompactGlass ? expansion : 1)
            }
        }
        .allowsHitTesting(false)
    }
    @ViewBuilder private var compactSurface: some View {
        if #available(iOS 26.0, *) {
            Color.clear
                .ignoresSafeArea()
                .glassEffect(.regular, in: CompactCapsuleShape())
        } else {
            CompactCapsuleShape().fill(.regularMaterial).ignoresSafeArea()
        }
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

/// Only the header crossfades with compact controls. List colors stay opaque
/// while the native sheet reveals/clips rows at its moving bottom edge.
struct JourneyContentReveal: View {
    let headerProgress: Double
    let headerHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(.black).opacity(headerProgress).frame(height: headerHeight)
            Rectangle().fill(.black)
        }
    }
}
