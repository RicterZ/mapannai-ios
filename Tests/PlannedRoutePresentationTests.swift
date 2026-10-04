import XCTest
import MapKit
@testable import MapAnNai

final class PlannedRoutePresentationTests: XCTestCase {
    static func point(_ x: Double, _ y: Double) -> Coordinate {
        Coordinate(latitude: 31.23 + y / 111195, longitude: 121.47 + x / (111195 * cos(31.23 * .pi / 180)))
    }
    static let fixture = [(0.0,0.0),(100,0),(200,2),(250,0),(250,40),(285,40),(285,5),(250,0),(350,0),(350,150),(390,150),(420,152),(460,150),(460,190),(490,190),(490,150),(460,150),(600,150)].map(point)
    func testLocalLoopPruningPreservesEndpointsAndMajorBend() throws {
        let cleaned = try PlannedRoutePresentation.points(Self.fixture)
        XCTAssertEqual(cleaned.first, Self.fixture.first)
        XCTAssertEqual(cleaned.last, Self.fixture.last)
        XCTAssertLessThan(cleaned.count, 8)
        XCTAssertTrue(cleaned.contains(Self.point(350, 0)))
        XCTAssertTrue(cleaned.contains(Self.point(350, 150)))
        XCTAssertFalse(cleaned.contains(Self.point(285, 40)))
    }
    func testLargeLoopAndSeparatedLegsArePreserved() throws {
        let large = [(0.0,0.0),(0,300),(300,300),(300,0),(0,0),(600,0)].map(Self.point)
        XCTAssertEqual(try PlannedRoutePresentation.points(large), large)
        let a = [Self.point(0,0), Self.point(40,0)]
        let b = [Self.point(40,0), Self.point(0,0)]
        XCTAssertEqual(try PlannedRoutePresentation.points(a), a)
        XCTAssertEqual(try PlannedRoutePresentation.points(b), b)
    }
    func testPlanningFallbackKeepsBezierAndDistanceUnmodified() async throws {
        let processing = RouteProcessing()
        let origin = Self.fixture.first!, destination = Self.fixture.last!
        let route = PlannedRoute(path: Self.fixture.map { RoutePoint(lat: $0.latitude, lng: $0.longitude) }, distance: 999, duration: 60)
        let result = try await processing.displayPoints(route, origin: origin, destination: destination)
        XCTAssertEqual(result.first, origin); XCTAssertEqual(result.last, destination)
        XCTAssertEqual(route.distance, 999)
        let fallback = PlannedRoute(path: route.path, distance: 999, duration: 60, fallback: "UNSUPPORTED_REGION")
        let curve = try await processing.displayPoints(fallback, origin: origin, destination: destination)
        XCTAssertEqual(curve, RouteGeometry.curve(origin, destination))
    }
    @MainActor func testMapComparisonScreenshots() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        let map = MKMapView(frame: window.bounds)
        let controller = UIViewController(); controller.view = map; window.rootViewController = controller; window.makeKeyAndVisible()
        let delegate = PresentationMapDelegate(); map.delegate = delegate
        let center = Self.point(300,100)
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude), latitudinalMeters: 1100, longitudinalMeters: 800), animated: false)
        for (name, points) in [("Before: planned geometry fixture", Self.fixture), ("After: shared pruning", try PlannedRoutePresentation.points(Self.fixture))] {
            map.removeOverlays(map.overlays)
            var coordinates = (name.hasPrefix("Before") ? RouteGeometry.smooth(points) : points).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
            map.addOverlay(MKPolyline(coordinates: &coordinates, count: coordinates.count))
            try await Task.sleep(for: .seconds(2))
            let image = UIGraphicsImageRenderer(bounds: map.bounds).image { _ in map.drawHierarchy(in: map.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
        window.isHidden = true
    }
}
@MainActor private final class PresentationMapDelegate: NSObject, MKMapViewDelegate {
    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        let renderer = MKPolylineRenderer(polyline: overlay as! MKPolyline)
        renderer.strokeColor = .systemOrange; renderer.lineWidth = 6; renderer.lineCap = .round; renderer.lineJoin = .round
        return renderer
    }
}
