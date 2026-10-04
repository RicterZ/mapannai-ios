import XCTest
import UIKit
@testable import MapAnNai

final class RouteMotionOverlayTests: XCTestCase {
    @MainActor func testSharedArrowOverlayReusesLayersAndCleansUp() async throws {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 600))
        let window = UIWindow(frame: view.bounds)
        let controller = UIViewController(); controller.view = view; window.rootViewController = controller; window.isHidden = false
        let overlay = RouteMotionOverlay()
        let routes = (0..<3).map { index in
            DisplayRoute(id: "day|0|\(index)", dayID: "day", tripID: "trip", colorIndex: index,
                points: [Coordinate(latitude: 31, longitude: 121 + Double(index) * 0.01),
                         Coordinate(latitude: 31, longitude: 121.01 + Double(index) * 0.01)], isPlanned: true)
        }
        let project: (Coordinate) -> CGPoint = { CGPoint(x: ($0.longitude - 121) * 10000, y: 100) }
        overlay.update(routes: routes, in: view, enabled: { true }, project: project)
        for _ in 0..<100 where (view.layer.sublayers ?? []).count < 3 {
            try await Task.sleep(for: .milliseconds(10))
        }
        let layers = try XCTUnwrap(view.layer.sublayers)
        XCTAssertEqual(layers.count, 3)
        XCTAssertTrue(layers.allSatisfy { $0 is CAShapeLayer })
        overlay.refresh()
        overlay.update(routes: routes, in: view, enabled: { true }, project: project)
        XCTAssertEqual(view.layer.sublayers, layers, "Repeated selection must retain layers and phase")
        overlay.stop()
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
        XCTAssertFalse(overlay.isRunning)
        window.isHidden = true
    }
    @MainActor func testObsoletePreparationCannotReinstallOldDayArrows() async throws {
        let view = UIView()
        let overlay = RouteMotionOverlay()
        let route = DisplayRoute(id: "old", dayID: "old", tripID: "trip", colorIndex: 0,
            points: (0...10000).map { Coordinate(latitude: 31, longitude: 120 + Double($0) / 10000) }, isPlanned: true)
        overlay.update(routes: [route], in: view, enabled: { true }, project: { _ in .zero })
        overlay.update(routes: [], in: view, enabled: { true }, project: { _ in .zero })
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(view.layer.sublayers?.isEmpty ?? true)
        overlay.stop()
    }
}
