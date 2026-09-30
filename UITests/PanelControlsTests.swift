import XCTest
import UIKit

final class PanelControlsTests: XCTestCase {
    @MainActor func testHeaderActionsAlignInAllDetentsAndSearchScrollsWithContent() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad)
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let collapse = app.buttons["itinerary-collapse"]
        let locate = app.buttons["itinerary-header-location"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 10))
        XCTAssertTrue(locate.exists)
        let addTrip = app.buttons["create-journey"]
        let settings = app.buttons["itinerary-header-settings"]
        XCTAssertFalse(addTrip.exists)
        XCTAssertFalse(settings.exists)
        XCTAssertLessThanOrEqual(locate.frame.maxX, collapse.frame.minX)
        assertHeaderAlignment(app)
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let searchY = search.frame.midY
        let list = app.collectionViews["itinerary-marker-list"]
        list.swipeUp()
        XCTAssertTrue(!search.isHittable || search.frame.midY < searchY - 20,
                      "搜索框应随行程内容向上滚动")
        list.swipeDown()
        XCTAssertEqual(collapse.frame.midY, locate.frame.midY, accuracy: 1)
        collapse.tap()
        XCTAssertEqual(collapse.label, "展开旅途")
        XCTAssertFalse(addTrip.exists)
        XCTAssertFalse(settings.exists)
        assertHeaderAlignment(app)
        collapse.tap()
        XCTAssertEqual(collapse.label, "收起旅途")
        assertHeaderAlignment(app)
        app.buttons["journey-back"].tap()
        let first = app.buttons["journey-day-day-1"]
        let second = app.buttons["journey-day-day-2"]
        XCTAssertFalse(addTrip.exists)
        XCTAssertFalse(settings.exists)
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
        assertHeaderAlignment(app)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Header actions aligned with title and scrollable search"; image.lifetime = .keepAlways; add(image)
        app.buttons["journey-back"].tap()
        XCTAssertTrue(addTrip.waitForExistence(timeout: 5))
        XCTAssertTrue(settings.exists)
        XCTAssertLessThanOrEqual(addTrip.frame.maxX, locate.frame.minX)
        XCTAssertLessThanOrEqual(locate.frame.maxX, settings.frame.minX)
        XCTAssertLessThanOrEqual(settings.frame.maxX, collapse.frame.minX)
        assertHeaderAlignment(app)
        addTrip.tap()
        XCTAssertTrue(app.navigationBars["创建旅行"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        collapse.tap()
        XCTAssertFalse(addTrip.exists)
        XCTAssertFalse(settings.exists)
        XCTAssertTrue(locate.isHittable)
        assertHeaderAlignment(app)
        collapse.tap()
        XCTAssertTrue(addTrip.exists)
        XCTAssertTrue(settings.exists)
        assertHeaderAlignment(app)
        let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        overview.name = "Overview-only add and settings"; overview.lifetime = .keepAlways; add(overview)
    }
    @MainActor private func assertHeaderAlignment(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let title = app.staticTexts["itinerary-panel-title"]
        XCTAssertTrue(title.exists, file: file, line: line)
        for id in ["create-journey", "itinerary-header-location", "itinerary-header-settings", "itinerary-collapse"] {
            let button = app.buttons[id]
            guard button.exists else { continue }
            XCTAssertEqual(button.frame.midY, title.frame.midY, accuracy: 2, file: file, line: line)
            XCTAssertGreaterThanOrEqual(button.frame.height, 43.9, file: file, line: line)
        }
    }
}
