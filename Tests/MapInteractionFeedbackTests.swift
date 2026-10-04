import XCTest
import UIKit
@testable import MapAnNai
final class MapInteractionFeedbackTests: XCTestCase {
    @MainActor func testRevealKeepsVisiblePointAndClampsCoveredPoint() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 800)
        let insets = UIEdgeInsets(top: 40, left: 0, bottom: 400, right: 0)
        XCTAssertEqual(MapInteractionFeedback.revealTarget(CGPoint(x: 80, y: 150), bounds: bounds, insets: insets), CGPoint(x: 80, y: 150))
        XCTAssertEqual(MapInteractionFeedback.revealTarget(CGPoint(x: 200, y: 650), bounds: bounds, insets: insets), CGPoint(x: 200, y: 356))
    }
    @MainActor func testPOIClaimCancelsPendingRoute() async {
        let arbiter = MapTapArbiter()
        var opened = false
        arbiter.scheduleRoute { opened = true }
        arbiter.claim()
        try? await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(opened)
    }
}
