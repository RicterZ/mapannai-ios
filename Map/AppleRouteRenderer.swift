import MapKit

/// Paints direction glyphs in the same renderer and context as the colored route.
/// MapKit transforms and clips the complete painted route as one overlay.
final class AppleRouteRenderer: MKPolylineRenderer {
    private let glyphLock = NSLock()
    private var glyphs: [[MKMapPoint]] = []
    func updateGlyphs(_ coordinates: [[Coordinate]]) {
        let next = coordinates.map { $0.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) } }
        glyphLock.lock(); glyphs = next; glyphLock.unlock()
        setNeedsDisplay()
    }
    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard zoomScale > 0 else { return }
        if path == nil { createPath() }
        guard let path else { return }
        // Draw both strokes explicitly in the same map-coordinate context. Calling the
        // native polyline draw and then appending CGContext drawing mixes two scale paths.
        context.saveGState()
        context.beginPath(); context.addPath(path)
        context.setStrokeColor((strokeColor ?? .systemBlue).cgColor)
        context.setLineWidth(lineWidth / zoomScale)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.strokePath(); context.restoreGState()
        glyphLock.lock(); let snapshot = glyphs; glyphLock.unlock()
        guard !snapshot.isEmpty else { return }
        context.saveGState()
        // Clip to this route's colored stroke; nearby routes never paint each other's arrows.
        context.beginPath()
        context.addPath(path.copy(strokingWithWidth: lineWidth / zoomScale, lineCap: .round, lineJoin: .round, miterLimit: 10))
        context.clip()
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(RouteArrowAppearance.strokeWidth / zoomScale)
        context.setLineCap(.round); context.setLineJoin(.round)
        context.beginPath()
        for glyph in snapshot {
            for (index, mapPoint) in glyph.enumerated() {
                let point = self.point(for: mapPoint)
                if index == 0 { context.move(to: point) } else { context.addLine(to: point) }
            }
        }
        context.strokePath(); context.restoreGState()
    }
}
