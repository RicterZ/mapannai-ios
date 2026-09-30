import SwiftUI

enum Theme {
    static let ink = Color(red: 0.12, green: 0.17, blue: 0.25)
    static let accent = Color(red: 0.10, green: 0.48, blue: 0.72)
    static let paper = Color(red: 0.92, green: 0.96, blue: 0.99)
    static let console = Color.white
    static let consoleRaised = Color(red: 0.94, green: 0.97, blue: 1.0)
    static let cyan = Color(red: 0.20, green: 0.57, blue: 0.82)
    static let pink = Color(red: 0.93, green: 0.55, blue: 0.72)
    static let muted = Color(red: 0.48, green: 0.55, blue: 0.63)
    static let text = Color(red: 0.19, green: 0.28, blue: 0.39)
    static let palette: [Color] = [.init(red: 0.08, green: 0.63, blue: 0.83), .init(red: 0.88, green: 0.35, blue: 0.66),
                                   .init(red: 0.46, green: 0.43, blue: 0.88), .init(red: 0.96, green: 0.57, blue: 0.27),
                                   .init(red: 0.16, green: 0.66, blue: 0.58), .init(red: 0.58, green: 0.44, blue: 0.72)]
    static func color(_ index: Int) -> Color { palette[((index % palette.count) + palette.count) % palette.count] }
}

extension View {
    func softSurface(fill: Color = Theme.consoleRaised, border: Color = Theme.cyan.opacity(0.18)) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(border, lineWidth: 1).allowsHitTesting(false))
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
    var body: some View {
        Text(icon.emoji).font(.system(size: 12))
            .frame(width: 28, height: 28)
            .background(selected ? Color(red: 0.145, green: 0.388, blue: 0.922) : icon.mapColor.opacity(0.75), in: Circle())
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .overlay(Circle().stroke(selected ? Theme.cyan : .clear, lineWidth: 2).padding(-3))
            .shadow(color: .black.opacity(0.16), radius: 3, y: 2)
    }
}
