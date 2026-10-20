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
        try await assertNoStacking(anchors: anchors, paths: paths, bounds: bounds)
    }

    func testClusteredPinsDoNotForceStackingOnPhone() async throws {
        let s = 393.0 / 471
        func a(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> ItineraryLayoutAnchor {
            ItineraryLayoutAnchor(id: id, x: x * s, y: y * s, width: w, height: h)
        }
        func p(_ x: Double, _ y: Double) -> ItineraryLayoutPoint { ItineraryLayoutPoint(x: x * s, y: y * s) }
        let anchors = [a("huang", 125, 248, 170, 60), a("d2802", 210, 380, 200, 74), a("air1", 112, 292, 200, 60), a("hohhot", 127, 290, 150, 46),
                       a("d2773", 290, 620, 200, 74), a("hong", 253, 618, 150, 46), a("gulou", 320, 425, 220, 76), a("dongfang", 335, 430, 220, 76),
                       a("air2", 235, 820, 190, 46)]
        let paths = [[p(125, 248), p(320, 425), p(253, 618), p(235, 820)], [p(112, 292), p(335, 430)], [p(127, 290), p(305, 268)], [p(320, 425), p(235, 820)]]
        let bounds = ItineraryLayoutBounds(left: 12, top: 90, right: 381, bottom: 806)
        let result = try await assertNoStacking(anchors: anchors, paths: paths, bounds: bounds)
        let leaders = result.map { hypot($0.end.x - $0.x, $0.end.y - $0.y) }
        XCTAssertLessThan(leaders.reduce(0, +) / Double(leaders.count), 150, "\(leaders)")
        var covered = 0.0
        for card in result {
            for path in paths {
                for (a, b) in zip(path, path.dropFirst()) {
                    let steps = Int(hypot(b.x - a.x, b.y - a.y) / 2) + 1
                    for k in 0..<steps {
                        let t = Double(k) / Double(steps), x = a.x + (b.x - a.x) * t, y = a.y + (b.y - a.y) * t
                        if x > card.left, x < card.left + card.width, y > card.top, y < card.top + card.height { covered += hypot(b.x - a.x, b.y - a.y) / Double(steps) }
                    }
                }
            }
        }
        XCTAssertLessThan(covered, 150, "covered route length \(covered)")
        let coveredPins = result.reduce(0) { count, card in
            count + anchors.filter { $0.id != card.id && $0.x > card.left && $0.x < card.left + card.width && $0.y > card.top && $0.y < card.top + card.height }.count
        }
        XCTAssertEqual(coveredPins, 0)
    }

    @discardableResult
    private func assertNoStacking(anchors: [ItineraryLayoutAnchor], paths: [[ItineraryLayoutPoint]], bounds: ItineraryLayoutBounds) async throws -> [ItineraryLayoutPlacement] {
        let result = try await ItineraryCardLayout().layout(anchors: anchors, bounds: bounds, paths: paths, previous: [])
        XCTAssertEqual(result.count, anchors.count)
        for (i, x) in result.enumerated() {
            for y in result[(i + 1)...] {
                let overlap = x.left < y.left + y.width && x.left + x.width > y.left && x.top < y.top + y.height && x.top + x.height > y.top
                XCTAssertFalse(overlap, "\(x.id) overlaps \(y.id)")
            }
        }
        return result
    }
}
