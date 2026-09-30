import XCTest
import UIKit

final class JourneySwitchingTests: XCTestCase {
    @MainActor func testRepeatedBackAndForwardKeepsStablePagesAndRoundControls() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        for _ in 0..<3 {
            let back = app.buttons["journey-back"]
            XCTAssertTrue(back.waitForExistence(timeout: 10))
            XCTAssertEqual(back.frame.width, back.frame.height, accuracy: 3)
            back.tap()
            let day = app.buttons["journey-day-day-1"]
            XCTAssertTrue(day.waitForExistence(timeout: 5))
            day.tap()
            XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        }
        app.buttons["journey-back"].tap()
        app.buttons["journey-back"].tap()
        let create = app.buttons["create-journey"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertEqual(create.frame.width, create.frame.height, accuracy: 3)
        app.buttons["journey-demo-trip"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Stable native journey controls"; shot.lifetime = .keepAlways; add(shot)
    }
}
