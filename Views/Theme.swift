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
    static let routeDividerColor = Color(uiColor: .label).opacity(0.25)
    static let routeDividerHeight: CGFloat = 0.5
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
    var themeColor: Color {
        switch self {
        case .activity: .orange
        case .location: .pink
        case .hotel: .indigo
        case .shopping: .purple
        case .food: .brown
        case .landmark: .teal
        case .park: .green
        case .natural: .mint
        case .culture: .red
        case .transit: .blue
        }
    }
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
        PlaceIconView(emoji: icon.emoji, size: 16).opacity(compact ? 0 : 1)
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

// Short-tip map balloons share an exact anchor and a transparent 44pt hit target.
enum SearchPinAppearance {
    // The dot at y=54 is the geographic anchor; the label floats above it.
    static func image(name: String) -> UIImage {
        let font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        let width = min(220, max(72, (name as NSString).size(withAttributes: [.font: font]).width + 36))
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: 64)).image { context in
            let cg = context.cgContext
            let ink = UIColor(red: 0.16, green: 0.15, blue: 0.14, alpha: 1)
            cg.setStrokeColor(ink.withAlphaComponent(0.65).cgColor)
            cg.setLineWidth(1.5)
            cg.move(to: CGPoint(x: width/2, y: 36)); cg.addLine(to: CGPoint(x: width/2, y: 54)); cg.strokePath()
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 5, color: UIColor.black.withAlphaComponent(0.2).cgColor)
            ink.setFill()
            UIBezierPath(roundedRect: CGRect(x: 6, y: 5, width: width-12, height: 32), cornerRadius: 11).fill()
            cg.restoreGState()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center; paragraph.lineBreakMode = .byTruncatingTail
            (name as NSString).draw(in: CGRect(x: 18, y: 13, width: width-36, height: 18),
                                   withAttributes: [.font: font, .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: width/2-6, y: 48, width: 12, height: 12)).fill()
            ink.setFill()
            UIBezierPath(ovalIn: CGRect(x: width/2-4, y: 50, width: 8, height: 8)).fill()
        }
    }
}

/// Mirrors Web place and trip presentation assets; persisted emoji values are untouched.
enum PlaceIconAssets {
    static func name(for emoji: String) -> String? {
        switch emoji.replacingOccurrences(of: "\u{FE0F}", with: "") {
        case "⛩": "Place-shrine"
        case "🎯": "Place-activity"
        case "📍": "Place-location"
        case "🏨": "Place-hotel"
        case "🛍": "Place-shopping"
        case "🍜": "Place-food"
        case "🌆": "Place-landmark"
        case "🎡": "Place-park"
        case "🗻": "Place-natural"
        case "🚉": "Place-transit"
        case "✈": "Place-plane"
        case "📅": "Place-calendar"
        case "🗺": "Place-map"
        case "🚞": "Trip-railway"
        case "🚢": "Trip-ship"
        case "🚗": "Trip-car"
        case "🏍": "Trip-motorcycle"
        case "🏕": "Trip-camping"
        case "🏖": "Trip-beach"
        case "🏯": "Trip-japanese-castle"
        case "🎒": "Trip-backpack"
        case "🍣": "Trip-sushi"
        case "🍲": "Trip-hot-pot"
        case "🍛": "Trip-curry"
        case "🍖": "Trip-meat"
        case "🚲": "Trip-bicycle"
        case "🚐": "Trip-van"
        case "⛵": "Trip-sailboat"
        case "🚠": "Trip-cable-car"
        case "🎈": "Trip-balloon"
        case "🏜": "Trip-desert"
        case "🌋": "Trip-volcano"
        case "🏝": "Trip-island"
        case "🌌": "Trip-night-sky"
        case "🌸": "Trip-blossom"
        case "🏰": "Trip-castle"
        case "🗼": "Trip-tower"
        case "🕌": "Trip-mosque"
        case "🗽": "Trip-statue-liberty"
        case "🎿": "Trip-ski"
        case "🤿": "Trip-diving"
        case "🏄": "Trip-surf"
        case "🥾": "Trip-hiking-boot"
        case "♨": "Trip-hot-spring"
        case "🎭": "Trip-theatre"
        case "🎨": "Trip-art"
        case "🎪": "Trip-circus"
        case "🎶": "Trip-music"
        case "🐼": "Trip-panda"
        case "🐘": "Trip-elephant"
        case "🐋": "Trip-whale"
        case "🦒": "Trip-giraffe"
        case "🐧": "Trip-penguin"
        case "☕": "Trip-coffee"
        case "🍷": "Trip-wine"
        case "🍺": "Trip-beer"
        case "🥐": "Trip-croissant"
        case "🍕": "Trip-pizza"
        case "🇨🇳": "Trip-flag-cn"
        case "🇯🇵": "Trip-flag-jp"
        case "🇰🇷": "Trip-flag-kr"
        case "🇸🇬": "Trip-flag-sg"
        case "🇹🇭": "Trip-flag-th"
        case "🇺🇸": "Trip-flag-us"
        case "🇫🇷": "Trip-flag-fr"
        case "🇬🇧": "Trip-flag-gb"
        case "🇮🇹": "Trip-flag-it"
        case "🇩🇪": "Trip-flag-de"
        default: nil
        }
    }
}
struct PlaceIconView: View {
    let emoji: String
    var size: CGFloat = 24
    var body: some View {
        Group {
            if let asset = PlaceIconAssets.name(for: emoji) {
                Image(asset).resizable().scaledToFit()
            } else { Text(emoji).font(.system(size: size)) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
