import XCTest

final class SearchReturnTests: XCTestCase {
    @MainActor func testCompactBackKeepsCapsuleAndReturnsToOverview() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        let panel = app.otherElements["phone-itinerary-panel"]
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 550)))
        XCTAssertTrue(app.buttons["date-selector"].waitForExistence(timeout: 5))
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            panel.frame.height < 150
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 5), .completed)
        let detailHeight = panel.frame.height
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 5))
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["compact-create-journey"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["itinerary-panel-title"].label, "我的旅途")
        XCTAssertTrue(app.staticTexts["journey-overview-subtitle"].exists)
        let sameHeight = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(panel.frame.height - detailHeight) <= 1
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [sameHeight], timeout: 5), .completed)
        XCTAssertLessThan(panel.frame.height, 200)
    }

    @MainActor func testOverviewCapsuleSubtitle() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap()
        app.buttons["journey-back"].tap()
        app.buttons["close-journey"].tap()
        XCTAssertTrue(app.staticTexts["旅の目的地は、まだ見ぬ地平線の向こうに"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["compact-create-journey"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "My Trips capsule with Japanese subtitle"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor func testSearchReturnsToCompactAndExpandedJourney() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["itinerary-search"].waitForExistence(timeout: 10))
        let panel = app.otherElements["phone-itinerary-panel"]
        func dragDown() {
            let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 550)))
        }
        dragDown()
        XCTAssertTrue(app.buttons["date-selector"].waitForExistence(timeout: 5))
        app.buttons["itinerary-search"].tap()
        XCTAssertTrue(app.buttons["close-place-picker"].waitForExistence(timeout: 5))
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["date-selector"].waitForExistence(timeout: 5))
        app.buttons["itinerary-search"].tap()
        XCTAssertTrue(app.buttons["close-place-picker"].waitForExistence(timeout: 5))
        dragDown()
        XCTAssertTrue(app.buttons["close-place-picker"].exists)
        XCTAssertFalse(app.buttons["date-selector"].exists)
        let searchUp = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        searchUp.press(forDuration: 0.1, thenDragTo: searchUp.withOffset(CGVector(dx: 0, dy: -300)))
        XCTAssertTrue(app.buttons["close-place-picker"].exists)
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["date-selector"].waitForExistence(timeout: 5))
        let start = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.02))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -300)))
        XCTAssertFalse(app.buttons["date-selector"].exists)
        app.buttons["itinerary-search"].tap()
        XCTAssertTrue(app.buttons["close-place-picker"].waitForExistence(timeout: 5))
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["date-selector"].exists)
        XCTAssertEqual(app.staticTexts["itinerary-panel-title"].label, "第1天")
        app.buttons["journey-back"].tap()
        app.buttons["journey-back"].tap()
        app.buttons["close-journey"].tap()
        let controls = app.otherElements["compact-journey-controls"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["itinerary-panel-title"].label, "我的旅途")
        XCTAssertTrue(app.buttons["compact-create-journey"].exists)
        XCTAssertEqual(app.buttons["itinerary-header-location"].frame.midY, controls.frame.midY, accuracy: 2)
        XCTAssertEqual(app.staticTexts["itinerary-panel-title"].frame.midX, app.frame.midX, accuracy: 2)
        app.buttons["itinerary-search"].tap()
        XCTAssertTrue(app.buttons["close-place-picker"].waitForExistence(timeout: 5))
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["itinerary-header-location"].frame.midY, controls.frame.midY, accuracy: 2)
        app.buttons["compact-create-journey"].tap()
        XCTAssertTrue(app.navigationBars["创建旅行"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }
}
