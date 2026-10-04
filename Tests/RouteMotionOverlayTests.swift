import XCTest
import UIKit
import MapKit
@testable import MapAnNai

final class RouteMotionOverlayTests: XCTestCase {
    @MainActor func testEmbeddedGlyphsKeepSizeAcrossZoom() throws {
        for zoom: CGFloat in [0.01, 0.02, 0.04] {
            var coordinates = [CLLocationCoordinate2D(latitude: 31, longitude: 121), CLLocationCoordinate2D(latitude: 31, longitude: 121.1)]
            let line = MKPolyline(coordinates: &coordinates, count: coordinates.count)
            let renderer = AppleRouteRenderer(polyline: line)
            renderer.lineWidth = 6; renderer.strokeColor = .systemBlue; renderer.showsDirections = true
            renderer.createPath()
            let start = renderer.point(for: line.points()[0])
            let format = UIGraphicsImageRendererFormat(); format.scale = 3
            let image = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 80), format: format).image { output in
                UIColor.white.setFill(); output.fill(CGRect(x: 0, y: 0, width: 320, height: 80))
                let context = output.cgContext
                context.translateBy(x: 10, y: 40); context.scaleBy(x: zoom, y: zoom)
                context.translateBy(x: -start.x, y: -start.y)
                renderer.draw(line.boundingMapRect, zoomScale: zoom, in: context)
            }
            let attachment = XCTAttachment(image: image); attachment.name = "Embedded route at \(zoom)"; attachment.lifetime = .keepAlways; add(attachment)
            XCTAssertEqual(image.scale, 3)
            let cg = try XCTUnwrap(image.cgImage)
            let data = try XCTUnwrap(cg.dataProvider?.data)
            let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
            // The white chevron intersects the route center at x=57pt, at every scale.
            let center = 120 * cg.bytesPerRow
            let white = (150..<180).filter { x in
                let offset = center + x * 4
                return bytes[offset] > 200 && bytes[offset + 1] > 200 && bytes[offset + 2] > 200
            }
            XCTAssertFalse(white.isEmpty, "Arrow must be painted at the same screen position at each zoom")
            let colored = (90..<150).filter { y in
                let offset = y * cg.bytesPerRow + 300 * 4
                return bytes[offset] < 240 || bytes[offset + 1] < 240 || bytes[offset + 2] < 240
            }
            XCTAssertEqual(colored.count, 18, "Native route remains 6pt at 3x")
        }
    }
    @MainActor func testActualMapRendering() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let map = MKMapView(frame: window.bounds)
        let controller = UIViewController(); controller.view = map; window.rootViewController = controller; window.makeKeyAndVisible()
        let delegate = RouteMapTestDelegate(); map.delegate = delegate
        var coordinates = [CLLocationCoordinate2D(latitude: 31.23, longitude: 121.46), CLLocationCoordinate2D(latitude: 31.23, longitude: 121.48)]
        let line = MKPolyline(coordinates: &coordinates, count: 2)
        map.addOverlay(line)
        for distance in [1200.0, 600, 2400] {
            map.setCamera(MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 31.23, longitude: 121.47), fromDistance: distance, pitch: 0, heading: 0), animated: false)
            try await Task.sleep(for: .seconds(2))
            let image = UIGraphicsImageRenderer(bounds: map.bounds).image { _ in map.drawHierarchy(in: map.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Actual MKMapView \(distance)"; attachment.lifetime = .keepAlways; add(attachment)
        }
        window.isHidden = true
    }
    @MainActor func testSDKTextureSizesAndSharedGlyph() {
        XCTAssertEqual(RouteMotionOverlay.texture(color: .systemBlue, google: false).size, CGSize(width: 6, height: 90))
        XCTAssertEqual(RouteMotionOverlay.texture(color: nil, google: true).scale, 3)
        XCTAssertEqual(RouteArrowAppearance.glyphPoints.count, 3)
    }
}

@MainActor private final class RouteMapTestDelegate: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = AppleRouteRenderer(polyline: overlay as! MKPolyline)
        renderer.lineWidth = 6; renderer.strokeColor = .systemOrange; renderer.showsDirections = true
        return renderer
    }
}
