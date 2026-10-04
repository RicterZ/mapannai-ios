import MapKit

/// One persistent native vector overlay, transformed by MapKit with the route.
/// No draw override: MapKit retains its vector rendering path instead of custom tiles.
final class AppleDirectionOverlay: NSObject, MKOverlay {
    let coordinate = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    let boundingMapRect = MKMapRect.world
}
final class AppleDirectionRenderer: MKOverlayPathRenderer {
    private let glyphLock = NSLock()
    private var glyphs: [[MKMapPoint]] = []
    func updateGlyphs(_ coordinates: [[Coordinate]]) {
        let next = coordinates.map { $0.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) } }
        glyphLock.lock(); glyphs = next; glyphLock.unlock()
        invalidatePath()
        setNeedsDisplay()
    }
    override func createPath() {
        glyphLock.lock(); let snapshot = glyphs; glyphLock.unlock()
        let result = CGMutablePath()
        for glyph in snapshot {
            for (index, mapPoint) in glyph.enumerated() {
                let point = self.point(for: mapPoint)
                if index == 0 { result.move(to: point) } else { result.addLine(to: point) }
            }
        }
        path = result
    }
}
