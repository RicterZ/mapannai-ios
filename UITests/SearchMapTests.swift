import XCTest
import UIKit

final class SearchMapTests: XCTestCase {
    @MainActor func testSearchPinsHalfSheetRepeatTapAndRetainedQuery() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let search = app.textFields["搜索地点"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("武康\n")
        let result = app.buttons["search-result-demo-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let pin = app.buttons["map-search-result-demo-0"]
        XCTAssertTrue(pin.exists)
        XCTAssertTrue(app.buttons["map-search-result-demo-1"].exists)
        result.tap()
        let name = app.textFields["地点名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "武康大楼")
        let bar = app.navigationBars["添加地点"]
        XCTAssertGreaterThan(bar.frame.minY, app.windows.firstMatch.frame.height * 0.35)
        let note = app.textViews["marker-note-editor"]
        XCTAssertLessThanOrEqual(note.frame.maxY, app.windows.firstMatch.frame.maxY - 20)
        XCTAssertTrue(pin.isHittable)
        screenshot("Search results and half-height editor")
        pin.tap()
        let expanded = NSPredicate { _, _ in bar.frame.minY < (UIDevice.current.userInterfaceIdiom == .pad ? 300 : app.windows.firstMatch.frame.height * 0.2) }
        expectation(for: expanded, evaluatedWith: bar); waitForExpectations(timeout: 5)
        XCTAssertEqual(name.value as? String, "武康大楼")
        XCTAssertLessThanOrEqual(note.frame.maxY, app.windows.firstMatch.frame.maxY - 20)
        screenshot("Repeated result tap expands editor")
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "武康")
        XCTAssertTrue(app.buttons["map-search-result-demo-0"].exists)
        app.buttons["清除搜索"].tap()
        XCTAssertFalse(app.buttons["map-search-result-demo-0"].exists)
    }
    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
