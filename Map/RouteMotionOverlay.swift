import UIKit

/// A single vector glyph source for SDK textures and the MapKit route renderer.
@MainActor enum RouteMotionOverlay {
    static let strokeWidth = RouteArrowAppearance.strokeWidth
    static let glyphPoints = RouteArrowAppearance.glyphPoints
    private static var textures: [String: UIImage] = [:]
    static func texture(color: UIColor?, google: Bool) -> UIImage {
        let key = "\(color?.description ?? "clear")/\(google)"
        if let image = textures[key] { return image }
        // AMap uses a vertical texture strip (matching the bundled traffic textures). Google images are square and
        // run top-to-bottom; transparent padding retains a thin glyph within the stroke.
        let size = google ? CGSize(width: 6, height: 6) : CGSize(width: 6, height: 90)
        let format = UIGraphicsImageRendererFormat(); format.scale = 3
        let image = UIGraphicsImageRenderer(size: size, format: format).image { output in
            let context = output.cgContext
            if let color { context.setFillColor(color.cgColor); context.fill(CGRect(origin: .zero, size: size)) }
            context.translateBy(x: size.width / 2, y: size.height / 2)
            // The SDKs advance their texture V coordinate in opposite directions.
            context.rotate(by: google ? .pi / 2 : -.pi / 2)
            context.setStrokeColor(UIColor.white.cgColor); context.setLineWidth(strokeWidth)
            context.setLineCap(.round); context.setLineJoin(.round)
            for (index, point) in glyphPoints.enumerated() {
                if index == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
            context.strokePath()
        }
        textures[key] = image; return image
    }
}
