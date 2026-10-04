import XCTest
@testable import MapAnNai

final class NativeRouteDropGeometryTests: XCTestCase {
    func testAnimationEligibilityIgnoresMovingRowsAndAbsorbsEdgeJitter() {
        var gate = NativeDropAnimationGate()
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 600)
        XCTAssertFalse(gate.update(point: CGPoint(x: 50, y: -2), bounds: bounds, hasPayload: true))
        XCTAssertTrue(gate.update(point: CGPoint(x: 50, y: 2), bounds: bounds, hasPayload: true))
        for y in [0.0, -2, 3, -10, 5] {
            XCTAssertTrue(gate.update(point: CGPoint(x: 50, y: y), bounds: bounds, hasPayload: true))
        }
        XCTAssertFalse(gate.update(point: CGPoint(x: 50, y: -13), bounds: bounds, hasPayload: true))
        XCTAssertFalse(gate.update(point: CGPoint(x: 50, y: -1), bounds: bounds, hasPayload: true))
        XCTAssertTrue(gate.update(point: CGPoint(x: 50, y: 300), bounds: bounds, hasPayload: true))
        XCTAssertFalse(gate.update(point: CGPoint(x: 50, y: 300), bounds: bounds, hasPayload: false))
    }
    func testWholeRouteAcceptsMarginsTrafficAndGaps() {
        let frames = ["0/header": CGRect(x: 20, y: 100, width: 300, height: 48),
                      "0/0": CGRect(x: 20, y: 148, width: 300, height: 120),
                      "0/1": CGRect(x: 20, y: 276, width: 300, height: 60)]
        for x in [2.0, 30.0, 350.0] {
            for y in stride(from: 100.0, through: 340.0, by: 5) {
                XCTAssertNotNil(NativeRouteDropGeometry.target(at: CGPoint(x: x, y: y), frames: frames))
            }
        }
        XCTAssertEqual(NativeRouteDropGeometry.target(at: CGPoint(x: 2, y: 270), frames: frames), "0/1/before")
        XCTAssertEqual(NativeRouteDropGeometry.target(at: CGPoint(x: 350, y: 335), frames: frames), "0/1/after")
        XCTAssertNil(NativeRouteDropGeometry.target(at: CGPoint(x: 20, y: 400), frames: frames))
    }
}
