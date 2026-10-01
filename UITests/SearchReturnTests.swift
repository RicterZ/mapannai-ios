import XCTest

final class SearchReturnTests: XCTestCase {
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
    }
}
