import XCTest
import UIKit

final class AIPlannerUITests: XCTestCase {
    @MainActor func testPadEntryToggleAndSettingsGuidance() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad sidebar")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let entry = app.buttons["open-ai-planner"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        XCTAssertTrue(app.buttons["ai-open-settings"].exists)
        app.buttons["ai-open-settings"].tap()
        let config = app.textFields["ai-api-url"]
        if !config.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(config.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ai-model"].exists)
        XCTAssertFalse(app.buttons["ai-configuration-link"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(app.otherElements["landscape-itinerary-sidebar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
    }
    @MainActor func testSwipeClosesAssistantAndRestoresJourney() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone system sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 10))
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        XCTAssertFalse(app.buttons["AI API 配置"].exists)
        XCTAssertTrue(app.otherElements["ai-configuration-prompt"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "AI centered setup and bottom composer"; shot.lifetime = .keepAlways; add(shot)
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
    }
}
