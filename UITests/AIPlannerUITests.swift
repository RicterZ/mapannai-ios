import XCTest
import UIKit

final class AIPlannerUITests: XCTestCase {
    @MainActor func testSwipeClosesAssistantAndRestoresJourney() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone system sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 10))
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        XCTAssertFalse(app.buttons["AI API 配置"].exists)
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
    }
}
