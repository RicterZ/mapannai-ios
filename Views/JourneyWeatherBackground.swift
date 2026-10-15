import SwiftUI

enum JourneyWeatherStyle {
    case sunny, cloudy, rainy, snowy, foggy, storm
    init?(code: Int) {
        switch code {
        case 0, 1: self = .sunny
        case 2, 3: self = .cloudy
        case 45, 48: self = .foggy
        case 51...67, 80...82: self = .rainy
        case 71...77, 85, 86: self = .snowy
        case 95...99: self = .storm
        default: return nil
        }
    }
}

// Fixed-size sky and ground, with a stretchable quiet center for photo cards.
struct JourneyWeatherBackground: View {
    let style: JourneyWeatherStyle
    var skyTop: CGFloat = 0
    @Environment(\.colorScheme) private var scheme
    private var rainy: Bool { style == .rainy || style == .storm }
    var body: some View {
        Canvas { context, size in
            let dark = scheme == .dark
            let base: Color = dark ? Color(uiColor: .secondarySystemGroupedBackground) :
                (style == .sunny ? Color(red: 1, green: 0.992, blue: 0.957) : Color(red: 0.968, green: 0.984, blue: 0.99))
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(base))
            let sky = CGPoint(x: size.width - 56, y: skyTop + 42)
            let opacity = dark ? 0.32 : 1.0
            if style == .sunny || style == .cloudy {
                context.fill(Path(ellipseIn: CGRect(x: sky.x - 29, y: sky.y - 29, width: 58, height: 58)),
                    with: .color(Color(red: 0.97, green: 0.86, blue: 0.54).opacity(opacity)))
            }
            if style != .sunny {
                var cloud = Path()
                cloud.addRoundedRect(in: CGRect(x: sky.x - 44, y: skyTop + 40, width: 72, height: 25), cornerSize: CGSize(width: 14, height: 14))
                cloud.addEllipse(in: CGRect(x: sky.x - 32, y: skyTop + 25, width: 36, height: 36))
                cloud.addEllipse(in: CGRect(x: sky.x - 6, y: skyTop + 32, width: 30, height: 30))
                context.fill(cloud, with: .color(Color(red: 0.82, green: 0.9, blue: 0.94).opacity(opacity)))
            }
            if rainy || style == .snowy {
                for i in 0..<3 {
                    let x = sky.x - 26 + CGFloat(i) * 16
                    if style == .snowy {
                        context.fill(Path(ellipseIn: CGRect(x: x, y: skyTop + 75, width: 4, height: 4)), with: .color(.gray.opacity(0.3)))
                    } else {
                        var drop = Path(); drop.move(to: CGPoint(x: x, y: skyTop + 74)); drop.addLine(to: CGPoint(x: x - 4, y: skyTop + 83))
                        context.stroke(drop, with: .color(.blue.opacity(0.2)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    }
                }
            }
            for layer in 0..<2 {
                let y = size.height - CGFloat(layer == 0 ? 38 : 20)
                var hill = Path(); hill.move(to: CGPoint(x: 0, y: y))
                hill.addQuadCurve(to: CGPoint(x: size.width * 0.55, y: y + 8), control: CGPoint(x: size.width * 0.25, y: y - 32))
                hill.addQuadCurve(to: CGPoint(x: size.width, y: y - 10), control: CGPoint(x: size.width * 0.8, y: y + 30))
                hill.addLine(to: CGPoint(x: size.width, y: size.height)); hill.addLine(to: CGPoint(x: 0, y: size.height)); hill.closeSubpath()
                let tint = style == .sunny ? Color(red: 0.85, green: 0.9, blue: 0.74) : Color(red: 0.8, green: 0.88, blue: 0.87)
                context.fill(hill, with: .color(tint.opacity((layer == 0 ? 0.5 : 0.7) * opacity)))
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}
