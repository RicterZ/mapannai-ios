import XCTest
@testable import MapAnNai

final class RouteDirectionArrowTests: XCTestCase {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
    func testStaticArrowsHaveExactSpacingAcrossZoom() throws {
        for length in [100.0, 1000.0] {
            let path = RouteDirectionPath(points: [.zero, CGPoint(x: length, y: 0)])
            let start = try XCTUnwrap(path.arrows(timestamp: 0.5, reducedMotion: false, bounds: bounds).first)
            let end = try XCTUnwrap(path.arrows(timestamp: 1.5, reducedMotion: false, bounds: bounds).first)
            XCTAssertEqual(end.position.x - start.position.x, 0, accuracy: 0.001)
            XCTAssertEqual(start.angle, 0)
            let arrows = path.arrows(timestamp: 1, reducedMotion: false, bounds: bounds)
            for pair in zip(arrows, arrows.dropFirst()) { XCTAssertEqual(pair.1.position.x - pair.0.position.x, 90, accuracy: 0.001) }
        }
    }
    func testBendUsesLocalDirectionAndReducedMotionIsStatic() throws {
        let path = RouteDirectionPath(points: [.zero, CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)])
        let first = path.arrows(timestamp: 0, reducedMotion: true, bounds: bounds)
        let later = path.arrows(timestamp: 100, reducedMotion: true, bounds: bounds)
        XCTAssertEqual(first.count, 2)
        XCTAssertEqual(first[0].angle, 0, accuracy: 0.001)
        XCTAssertEqual(first[1].angle, .pi / 2, accuracy: 0.001)
        XCTAssertEqual(first.map(\.position), later.map(\.position))
        XCTAssertTrue(first.allSatisfy { $0.opacity == 1 })
    }
    func testHugeOffscreenPathOnlyProducesVisibleArrows() {
        let path = RouteDirectionPath(points: [CGPoint(x: -100000000, y: 100), CGPoint(x: 100000000, y: 100)], bounds: bounds)
        XCTAssertLessThanOrEqual(path.arrows(timestamp: 1, reducedMotion: false, bounds: bounds).count, 12)
        XCTAssertTrue(RouteDirectionPath(points: [.zero, .zero]).arrows(timestamp: 1, reducedMotion: false, bounds: bounds).isEmpty)
    }
}
