import XCTest
import UIKit

final class PanelControlsTests: XCTestCase {
    @MainActor func testCollapseIsImmediatelyLeftOfLocationAndDaysHaveOneDate() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let collapse = app.buttons["itinerary-collapse"]
        let locate = app.buttons["itinerary-header-location"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 10))
        XCTAssertTrue(locate.exists)
        XCTAssertLessThan(collapse.frame.maxX, locate.frame.minX)
        XCTAssertEqual(collapse.frame.midY, locate.frame.midY, accuracy: 1)
        collapse.tap()
        XCTAssertEqual(collapse.label, "展开旅途")
        collapse.tap()
        XCTAssertEqual(collapse.label, "收起旅途")
        app.buttons["journey-back"].tap()
        let first = app.buttons["journey-day-day-1"]
        let second = app.buttons["journey-day-day-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.staticTexts["第1天"].exists)
        XCTAssertTrue(second.staticTexts["第2天"].exists)
        XCTAssertEqual(first.staticTexts.matching(identifier: "2026-10-01").count, 1)
        XCTAssertEqual(second.staticTexts.matching(identifier: "2026-10-02").count, 1)
        let handle = app.buttons["itinerary-panel-toggle"]
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
        XCTAssertEqual(collapse.frame.midY, locate.frame.midY, accuracy: 1)
        XCTAssertTrue(collapse.isHittable)
        XCTAssertTrue(locate.isHittable)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Day numbering and collapse beside location"; image.lifetime = .keepAlways; add(image)
    }
}
