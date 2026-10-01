import XCTest
import UIKit

final class AIPlannerUITests: XCTestCase {
    @MainActor func testHiddenWorkspaceLayoutAndConfiguration() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--ai-planner-demo"]; app.launch()
        let close = app.buttons["close-ai-planner"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        let input = app.textFields["ai-message-input"]
        XCTAssertTrue(input.exists)
        if isPad { XCTAssertGreaterThan(close.frame.midX, app.frame.width * 0.5) }
        else { XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.35) }
        app.buttons["AI API 配置"].tap()
        XCTAssertTrue(app.textFields["ai-api-url"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["ai-api-key"].exists)
        XCTAssertTrue(app.textFields["ai-model"].exists)
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        if isPad {
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(close.frame.midX, app.frame.width * 0.5)
        }
        close.tap()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        app.terminate()
        app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["open-ai-planner"].exists)
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(app.buttons["close-ai-planner"].waitForExistence(timeout: 5))
        app.buttons["close-ai-planner"].tap()
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
    }
}
