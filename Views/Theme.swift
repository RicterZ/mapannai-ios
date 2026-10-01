import SwiftUI
import UIKit

enum Theme {
    static let ink = Color(uiColor: .label)
    static let accent = Color(uiColor: .systemBlue)
    static let paper = Color(uiColor: .secondarySystemBackground)
    static let console = Color(uiColor: .systemBackground)
    static let consoleRaised = Color(uiColor: .tertiarySystemFill)
    static let cyan = Color(uiColor: .systemBlue)
    static let pink = Color(uiColor: .systemPink)
    static let muted = Color(uiColor: .secondaryLabel)
    static let text = Color(uiColor: .label)
    static let separator = Color(uiColor: .separator)
    static let palette: [Color] = [.init(red: 0.08, green: 0.63, blue: 0.83), .init(red: 0.88, green: 0.35, blue: 0.66),
                                   .init(red: 0.46, green: 0.43, blue: 0.88), .init(red: 0.96, green: 0.57, blue: 0.27),
                                   .init(red: 0.16, green: 0.66, blue: 0.58), .init(red: 0.58, green: 0.44, blue: 0.72)]
    static func color(_ index: Int) -> Color { palette[((index % palette.count) + palette.count) % palette.count] }
}

extension View {
    /// Apply inside a Button label so empty row space participates in hit testing.
    func fullRowActionLabel() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
    }
    func softSurface(fill: Color = Theme.consoleRaised, border: Color = Theme.separator.opacity(0.35)) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(border, lineWidth: 1).allowsHitTesting(false))
    }
}
/// Keep both parts of destructive menu labels red even under a blue navigation tint.
struct DestructiveMenuButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .renderingMode(.original)
                    .foregroundStyle(.red)
            }.foregroundStyle(.red)
        }.tint(.red)
    }
}

struct MarkerRow: View {
    let marker: Marker
    var subtitle: String? = nil
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        let dark = colorScheme == .dark
        HStack(spacing: 12) {
            MapMarkerCircle(icon: marker.icon).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 5) {
                Text(marker.title).font(.subheadline.weight(.semibold)).foregroundStyle(dark ? Theme.text : Theme.ink)
                if let caption = subtitle ?? marker.content.address, !caption.isEmpty {
                    Text(caption).font(.caption).foregroundStyle(dark ? Theme.muted : .secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(dark ? Theme.muted : .secondary)
        }.padding(.vertical, 5)
    }
}

struct PanelCloseButton: View {
    var identifier: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted).frame(width: 30, height: 30)
                .background(Theme.consoleRaised, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("关闭").accessibilityIdentifier(identifier)
    }
}

/// Keep our solid close button from being layered over a second toolbar glass circle.
struct PanelCloseToolbarItem: ToolbarContent {
    let identifier: String
    var placement: ToolbarItemPlacement = .cancellationAction
    var disabled = false
    let action: () -> Void

    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: placement) {
                PanelCloseButton(identifier: identifier, action: action).disabled(disabled)
            }.sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: placement) {
                PanelCloseButton(identifier: identifier, action: action).disabled(disabled)
            }
        }
    }
}

extension MarkerIcon {
    var mapColor: Color {
        Color(red: Double((colorRGB >> 16) & 255) / 255,
              green: Double((colorRGB >> 8) & 255) / 255, blue: Double(colorRGB & 255) / 255)
    }
}
struct MapMarkerCircle: View {
    let icon: MarkerIcon
    var selected = false
    var compact = false
    var body: some View {
        Text(compact ? "" : icon.emoji).font(.system(size: 12))
            .frame(width: 28, height: 28)
            .background(selected ? Color(red: 0.145, green: 0.388, blue: 0.922) : icon.mapColor.opacity(0.75), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Circle().stroke(selected && !compact ? Theme.cyan : .clear, lineWidth: 2).padding(-3))
            .shadow(color: .black.opacity(compact ? 0 : 0.16), radius: 3, y: 2)
            .scaleEffect(compact ? 10.0 / 28.0 : 1)
    }
}

struct PanelChevron: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

// Compact result dots sit on the actual coordinate, with a larger transparent tap target.
enum SearchPinAppearance {
    static func image(selected: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { _ in
            let diameter: CGFloat = selected ? 16 : 10
            let rect = CGRect(x: (44 - diameter) / 2, y: (44 - diameter) / 2, width: diameter, height: diameter)
            let circle = UIBezierPath(ovalIn: rect)
            (selected ? UIColor(Theme.accent) : UIColor.systemRed).setFill(); circle.fill()
            UIColor.white.setStroke(); circle.lineWidth = 2; circle.stroke()
        }
    }
}
