import MapKit

/// Direction glyphs are drawn inside the route's own drawing context at current scale.
final class AppleRouteRenderer: MKPolylineRenderer {
    var showsDirections = false { didSet { if oldValue != showsDirections { setNeedsDisplay() } } }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale > 0 else { return }
        if path == nil { createPath() }
        guard let path else { return }
        context.saveGState()
        context.beginPath(); context.addPath(path)
        context.setStrokeColor((strokeColor ?? .systemBlue).cgColor)
        context.setLineWidth(lineWidth / zoomScale)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.strokePath(); context.restoreGState()
        guard showsDirections else { return }
        let points = (0..<polyline.pointCount).map { index -> CGPoint in
            let p = point(for: polyline.points()[index])
            return CGPoint(x: p.x * zoomScale, y: p.y * zoomScale)
        }
        let rect = self.rect(for: mapRect)
        let bounds = CGRect(x: rect.minX * zoomScale, y: rect.minY * zoomScale,
                            width: rect.width * zoomScale, height: rect.height * zoomScale)
        let directions = RouteDirectionPath(points: points, bounds: bounds)
        context.saveGState()
        context.beginPath()
        context.addPath(path.copy(strokingWithWidth: lineWidth / zoomScale, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.clip()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(RouteArrowAppearance.strokeWidth / zoomScale)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.beginPath()
        for arrow in directions.arrows(timestamp: 0, reducedMotion: true, bounds: bounds) {
            let c = cos(arrow.angle), s = sin(arrow.angle)
            for (index, p) in RouteArrowAppearance.glyphPoints.enumerated() {
                let vertex = CGPoint(x: (arrow.position.x + p.x * c - p.y * s) / zoomScale,
                                     y: (arrow.position.y + p.x * s + p.y * c) / zoomScale)
                if index == 0 { context.move(to: vertex) } else { context.addLine(to: vertex) }
            }
        }
        context.strokePath(); context.restoreGState()
    }
}
