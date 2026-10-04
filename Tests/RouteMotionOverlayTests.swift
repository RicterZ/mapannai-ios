import XCTest
import UIKit
import MapKit
@testable import MapAnNai

final class RouteMotionOverlayTests: XCTestCase {
    @MainActor func testNativeArrowsStayGeographicallyFixedDuringPanAndRegenerateOnZoom() async throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let overlay = RouteMotionOverlay()
        let route = DisplayRoute(id: "route", dayID: "day", tripID: "trip", colorIndex: 0,
            points: [Coordinate(latitude: 31, longitude: 121), Coordinate(latitude: 31, longitude: 121.03)], isPlanned: true)
        var pan: CGFloat = 0, scale: CGFloat = 10000, rotation: CGFloat = 0
        var publications: [[[Coordinate]]] = []
        var enabled = true
        overlay.update(routes: [route], in: view, enabled: { enabled },
            project: {
                let x = ($0.longitude - 121) * scale, y = ($0.latitude - 31) * scale
                return CGPoint(x: x * cos(rotation) - y * sin(rotation) + pan,
                               y: x * sin(rotation) + y * cos(rotation) + 100)
            },
            unproject: { Coordinate(latitude: 31 + ($0.y - 100) / scale, longitude: 121 + ($0.x - pan) / scale) },
            cameraKey: { log2(Double(scale)) }, publish: { publications.append($0) })
        XCTAssertEqual(publications.count, 1)
        XCTAssertEqual(publications[0].count, 3)
        let original = publications[0]
        pan = 25; overlay.refresh()
        XCTAssertEqual(publications.count, 1, "Pan must not update any native arrow overlay")
        XCTAssertEqual(publications[0], original)
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true, "No independent screen layer may follow the camera")
        pan = 10000; overlay.refresh()
        XCTAssertEqual(publications.count, 1, "Leaving the old viewport must not rebuild the arrows")
        for angle in [CGFloat.pi / 4, .pi / 2, .pi, .pi * 2] {
            rotation = angle; overlay.refresh()
            XCTAssertEqual(publications.count, 1, "Rotation must not resubmit native geometry")
            XCTAssertEqual(publications[0], original)
        }
        scale *= 1.0001; overlay.refresh()
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(publications.count, 1, "Tiny camera noise must not replace overlays")
        scale = 15000; overlay.refresh()
        scale = 20000; overlay.refresh()
        XCTAssertEqual(publications.count, 1, "Zoom keeps old native geometry until the camera settles")
        try await Task.sleep(for: .milliseconds(220))
        XCTAssertEqual(publications.count, 2)
        XCTAssertGreaterThan(publications[1].count, original.count)
        enabled = false; overlay.refresh()
        XCTAssertEqual(publications.last, [])
        overlay.stop()
    }
    @MainActor func testCompleteRouteArrowsExistOutsideInitialViewport() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let overlay = RouteMotionOverlay()
        let route = DisplayRoute(id: "route", dayID: "day", tripID: "trip", colorIndex: 0,
            points: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 1800)], isPlanned: true)
        var paths: [[Coordinate]] = []
        overlay.update(routes: [route], in: view, enabled: { true },
            project: { CGPoint(x: $0.longitude, y: 0) },
            unproject: { Coordinate(latitude: $0.y, longitude: $0.x) },
            cameraKey: { 1 }, publish: { paths = $0 })
        XCTAssertEqual(paths.count, 20)
        XCTAssertGreaterThan(paths.last![1].longitude, 1700)
        overlay.stop()
    }
    @MainActor func testArrowRendererUsesOnePersistentNativeVectorPath() {
        let overlay = AppleDirectionOverlay()
        let renderer = AppleDirectionRenderer(overlay: overlay)
        renderer.shouldRasterize = false
        renderer.strokeColor = .white; renderer.lineWidth = RouteArrowAppearance.strokeWidth
        let glyph = [Coordinate(latitude: 31, longitude: 121), Coordinate(latitude: 31.00001, longitude: 121.00001), Coordinate(latitude: 31.00002, longitude: 121)]
        renderer.updateGlyphs([glyph]); renderer.createPath()
        XCTAssertFalse(renderer.shouldRasterize)
        XCTAssertFalse(renderer.path.isEmpty)
        XCTAssertTrue(renderer.overlay === overlay)
        renderer.updateGlyphs([glyph, glyph]); renderer.createPath()
        XCTAssertTrue(renderer.overlay === overlay, "Zoom replaces path data, never the native overlay")
        renderer.updateGlyphs([]); renderer.createPath()
        XCTAssertTrue(renderer.path.isEmpty)
    }
    @MainActor func testMapKitZoomKeyIsIndependentOfRotation() {
        let map = MKMapView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let camera = MKMapCamera(lookingAtCenter: CLLocationCoordinate2D(latitude: 31, longitude: 121),
                                 fromDistance: 1200, pitch: 0, heading: 0)
        map.setCamera(camera, animated: false)
        let distance = map.camera.centerCoordinateDistance
        for angle in [45.0, 90, 180, 270, 359] {
            let rotated = map.camera.copy() as! MKMapCamera
            rotated.heading = angle
            map.setCamera(rotated, animated: false)
            XCTAssertEqual(map.camera.centerCoordinateDistance, distance, accuracy: max(distance, 1) * 0.000001,
                           "The adapter zoom key must not treat bearing changes as zoom")
        }
    }
    @MainActor func testRouteChangeAndStopClearNativeArrows() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let overlay = RouteMotionOverlay()
        let route = DisplayRoute(id: "route", dayID: "day", tripID: "trip", colorIndex: 0,
            points: [Coordinate(latitude: 0, longitude: 0), Coordinate(latitude: 0, longitude: 100)], isPlanned: true)
        var paths: [[Coordinate]] = []
        let project: (Coordinate) -> CGPoint = { CGPoint(x: $0.longitude, y: 100) }
        let unproject: (CGPoint) -> Coordinate = { Coordinate(latitude: $0.y - 100, longitude: $0.x) }
        overlay.update(routes: [route], in: view, enabled: { true }, project: project,
            unproject: unproject, cameraKey: { 1 }, publish: { paths = $0 })
        XCTAssertFalse(paths.isEmpty)
        overlay.update(routes: [], in: view, enabled: { true }, project: project,
            unproject: unproject, cameraKey: { 1 }, publish: { paths = $0 })
        XCTAssertTrue(paths.isEmpty)
        overlay.stop(); XCTAssertFalse(overlay.isRunning)
    }
}
