import XCTest
@testable import MapAnNai

final class ItineraryCardLayoutTests: XCTestCase {
    func testSharedJavaScriptEngineSupportsMeasuredCardsAndHysteresis() async throws {
        let engine = ItineraryCardLayout()
        let anchors = [ItineraryLayoutAnchor(id: "place:a", x: 500, y: 400, width: 208, height: 100)]
        let bounds = ItineraryLayoutBounds(left: 12, top: 16, right: 1000, bottom: 800)
        let paths = [[ItineraryLayoutPoint(x: 100, y: 400), ItineraryLayoutPoint(x: 900, y: 400)]]
        let result = try await engine.layout(anchors: anchors, bounds: bounds, paths: paths, previous: [])
        let p = try XCTUnwrap(result.first)
        XCTAssertEqual(p.width, 208)
        XCTAssertGreaterThanOrEqual(p.left, bounds.left)
        XCTAssertLessThanOrEqual(p.left + p.width, bounds.right)
        XCTAssertTrue(p.top + p.height < 400 || p.top > 400)
        XCTAssertTrue(p.end.x >= p.left && p.end.x <= p.left + p.width)
        let next = try await engine.layout(anchors: anchors, bounds: bounds, paths: paths, previous: result)
        XCTAssertEqual(next.first?.left, p.left)
        XCTAssertEqual(next.first?.top, p.top)
    }
}
