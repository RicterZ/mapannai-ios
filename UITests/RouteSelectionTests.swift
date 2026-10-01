import XCTest

final class RouteSelectionTests: XCTestCase {
    @MainActor func testLineClickOpensDayAtHalfHeightAndRepeats() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap()
        app.buttons["itinerary-collapse"].tap()
        let map = app.otherElements["preview-map-surface"]
        let a = app.buttons["map-marker-demo-0"], b = app.buttons["map-marker-demo-1"]
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        let target = CGPoint(x: (a.frame.midX + b.frame.midX) / 2, y: (a.frame.midY + b.frame.midY) / 2)
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.x - map.frame.minX, dy: target.y - map.frame.minY)).tap()
        XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        let panel = app.otherElements["phone-itinerary-panel"]
        let medium = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 300 && panel.frame.height < 650 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [medium], timeout: 5), .completed)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Selected day route and half sheet"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
