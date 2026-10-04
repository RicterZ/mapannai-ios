import UIKit

/// Shared raster artwork; SDK adapters only position and select annotations.
@MainActor enum MapMarkerAppearance {
    private static var cache: [String: UIImage] = [:]
    static func image(icon: MarkerIcon, compact: Bool, selected: Bool) -> UIImage {
        let key = "\(icon.rawValue)/\(compact)/\(selected)"
        if let image = cache[key] { return image }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44))
        let image = renderer.image { context in
            let cg = context.cgContext
            let rgb: UInt32 = selected ? 0x2563EB : icon.colorRGB
            let color = UIColor(red: CGFloat((rgb >> 16) & 255)/255,
                                green: CGFloat((rgb >> 8) & 255)/255, blue: CGFloat(rgb & 255)/255,
                                alpha: selected ? 1 : 0.75)
            let diameter: CGFloat = compact ? 10 : selected ? 30.8 : 28
            let circle = CGRect(x: (44-diameter)/2, y: (44-diameter)/2, width: diameter, height: diameter)
            cg.saveGState()
            if !compact { cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3, color: UIColor.black.withAlphaComponent(0.18).cgColor) }
            cg.setFillColor(color.cgColor); cg.fillEllipse(in: circle)
            cg.restoreGState()
            cg.setStrokeColor(UIColor.white.cgColor); cg.setLineWidth(compact ? 1 : 2)
            cg.strokeEllipse(in: circle.insetBy(dx: 1, dy: 1))
            if selected && !compact {
                cg.setStrokeColor(color.cgColor); cg.setLineWidth(2)
                cg.strokeEllipse(in: circle.insetBy(dx: -3, dy: -3))
            }
            if !compact {
                let text = icon.emoji as NSString
                let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 12)]
                let size = text.size(withAttributes: attrs)
                text.draw(at: CGPoint(x: (44-size.width)/2, y: (44-size.height)/2), withAttributes: attrs)
            }
        }
        cache[key] = image
        return image
    }
    static func draftImage(icon: MarkerIcon) -> UIImage {
        let symbol = icon == .location ? "circle" : icon.symbol
        let key = "draft/" + symbol
        if let image = cache[key] { return image }
        let image = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 48)).image { context in
            let cg = context.cgContext
            // One connected silhouette prevents the tail from blending into the base POI.
            let shape = UIBezierPath()
            shape.move(to: CGPoint(x: 22, y: 42))
            shape.addLine(to: CGPoint(x: 16, y: 34))
            shape.addCurve(to: CGPoint(x: 6, y: 19), controlPoint1: CGPoint(x: 10, y: 32), controlPoint2: CGPoint(x: 6, y: 26))
            shape.addCurve(to: CGPoint(x: 22, y: 3), controlPoint1: CGPoint(x: 6, y: 10), controlPoint2: CGPoint(x: 13, y: 3))
            shape.addCurve(to: CGPoint(x: 38, y: 19), controlPoint1: CGPoint(x: 31, y: 3), controlPoint2: CGPoint(x: 38, y: 10))
            shape.addCurve(to: CGPoint(x: 28, y: 34), controlPoint1: CGPoint(x: 38, y: 26), controlPoint2: CGPoint(x: 34, y: 32))
            shape.close()
            cg.saveGState()
            cg.setShadow(offset: CGSize(width: 0, height: 2), blur: 3,
                         color: UIColor.black.withAlphaComponent(0.25).cgColor)
            UIColor.systemBlue.setFill()
            shape.fill()
            cg.restoreGState()
            UIColor.white.setStroke()
            shape.lineWidth = 2
            shape.lineJoinStyle = .round
            shape.stroke()
            if let icon = UIImage(systemName: symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let size = icon.size
                icon.draw(in: CGRect(x: 22 - size.width / 2, y: 19 - size.height / 2,
                                     width: size.width, height: size.height))
            }
        }
        cache[key] = image
        return image
    }

}
