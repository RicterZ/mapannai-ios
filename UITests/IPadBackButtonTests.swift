import XCTest
import UIKit

final class IPadBackButtonTests: XCTestCase {
    @MainActor func testLandscapeBackRespondsToOneTapAcrossTouchTarget() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let sidebar = app.otherElements["landscape-itinerary-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        for offset in [CGVector(dx: -16, dy: 0), CGVector(dx: 16, dy: 0), CGVector(dx: 0, dy: -16), CGVector(dx: 0, dy: 16)] {
            let back = app.buttons["journey-back"]
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            back.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(offset).tap()
            let day = app.buttons["journey-day-day-1"]
            XCTAssertTrue(day.waitForExistence(timeout: 3), "One tap near the back icon must return to the trip")
            if !day.exists { return }
            day.tap()
            XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        }
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 3))
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["create-journey"].waitForExistence(timeout: 3))
    }
}
