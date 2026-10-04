import XCTest
import UIKit
import MapKit
@testable import MapAnNai

final class RouteMotionOverlayTests: XCTestCase {
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
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
        renderer.lineWidth = 6; renderer.strokeColor = .systemOrange
        return renderer
    }
}
