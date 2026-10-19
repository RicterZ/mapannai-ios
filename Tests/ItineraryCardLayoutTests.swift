import XCTest
@testable import MapAnNai

final class ItineraryCardLayoutTests: XCTestCase {
    func testNativeEngineSupportsMeasuredCardsAndHysteresis() async throws {
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

    func testBlockedCardsMoveNeighboursInsteadOfStackingOnPhone() async throws {
        let s = 393.0 / 471
        func a(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ItineraryLayoutAnchor {
            ItineraryLayoutAnchor(id: id, x: x * s, y: y * s, width: w, height: h)
        }
        func p(_ x: Double, _ y: Double) -> ItineraryLayoutPoint { ItineraryLayoutPoint(x: x * s, y: y * s) }
        let anchors = [a("a", 135, 237, 240, 58), a("b", 128, 330, 240, 72), a("c", 120, 272, 240, 58), a("d", 200, 560, 240, 72),
                       a("e", 262, 603, 240, 58), a("f", 330, 415, 240, 90), a("g", 245, 815, 240, 58)]
        let paths = [[p(135, 237), p(330, 415), p(262, 603), p(245, 815)], [p(120, 272), p(345, 418)], [p(137, 262), p(318, 262)]]
        let bounds = ItineraryLayoutBounds(left: 12, top: 90, right: 381, bottom: 806)
        let result = try await ItineraryCardLayout().layout(anchors: anchors, bounds: bounds, paths: paths, previous: [])
        XCTAssertEqual(result.count, anchors.count)
        for (i, x) in result.enumerated() {
            for y in result[(i + 1)...] {
                let overlap = x.left < y.left + y.width && x.left + x.width > y.left && x.top < y.top + y.height && x.top + x.height > y.top
                XCTAssertFalse(overlap, "\(x.id) overlaps \(y.id)")
            }
        }
    }
}
