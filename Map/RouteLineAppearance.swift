import UIKit

/// SDK adapters draw the same two strokes using these shared values.
enum RouteLineAppearance {
    static func width(selected: Bool, dashed: Bool = false) -> CGFloat { selected ? 6 : 3.5 }
    static func outlineWidth(selected: Bool, dashed: Bool = false) -> CGFloat { width(selected: selected, dashed: dashed) + 2 }
    static func color(_ index: Int) -> UIColor { UIColor(Theme.color(index)) }
    static func outline(_ index: Int) -> UIColor {
        let base = color(index)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        base.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * 0.35 + 0.65, green: g * 0.35 + 0.65, blue: b * 0.35 + 0.65, alpha: 1)
    }
}
