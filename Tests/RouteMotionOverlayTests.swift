import XCTest
import UIKit
@testable import MapAnNai

final class RouteMotionOverlayTests: XCTestCase {
    @MainActor func testNativeArrowsStayGeographicallyFixedDuringPanAndRegenerateOnZoom() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let overlay = RouteMotionOverlay()
        let route = DisplayRoute(id: "route", dayID: "day", tripID: "trip", colorIndex: 0,
            points: [Coordinate(latitude: 31, longitude: 121), Coordinate(latitude: 31, longitude: 121.03)], isPlanned: true)
        var pan: CGFloat = 0, scale: CGFloat = 10000
        var publications: [[[Coordinate]]] = []
        var enabled = true
        overlay.update(routes: [route], in: view, enabled: { enabled },
            project: { CGPoint(x: ($0.longitude - 121) * scale + pan, y: ($0.latitude - 31) * scale + 100) },
            unproject: { Coordinate(latitude: 31 + ($0.y - 100) / scale, longitude: 121 + ($0.x - pan) / scale) },
            cameraKey: { Double(scale) }, publish: { publications.append($0) })
        XCTAssertEqual(publications.count, 1)
        XCTAssertEqual(publications[0].count, 3)
        let original = publications[0]
        pan = 25; overlay.refresh()
        XCTAssertEqual(publications.count, 1, "Pan must not update any native arrow overlay")
        XCTAssertEqual(publications[0], original)
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true, "No independent screen layer may follow the camera")
        scale = 20000; overlay.refresh()
        XCTAssertEqual(publications.count, 2)
        XCTAssertGreaterThan(publications[1].count, original.count)
        enabled = false; overlay.refresh()
        XCTAssertEqual(publications.last, [])
        overlay.stop()
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
