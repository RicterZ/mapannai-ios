import XCTest
import UIKit

final class SearchMapTests: XCTestCase {
    @MainActor func testSelectionAndEditingStayInOneWorkspace() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertFalse(app.textFields["地点名称"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "add-search-place-demo-3").count, 1)
        XCTAssertFalse(app.buttons["edit-search-place"].exists)
        let pin = app.buttons["map-search-result-demo-3"]
        XCTAssertTrue(pin.isHittable); pin.tap()
        let name = app.textFields["地点名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "静安寺")
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
        if UIDevice.current.userInterfaceIdiom == .phone {
            let half = NSPredicate { _, _ in search.frame.minY > app.windows.firstMatch.frame.height * 0.4 }
            expectation(for: half, evaluatedWith: search); waitForExpectations(timeout: 5)
            XCTAssertTrue(pin.isHittable)
        }
        screenshot("Return to half-height search without selection fill")
        XCTAssertTrue(result.exists)
        app.buttons["close-place-picker"].tap()
        XCTAssertFalse(pin.exists)
        let dayAdd = app.buttons["day-search-add-place"]
        let list = app.collectionViews["itinerary-marker-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        for _ in 0..<4 where !dayAdd.isHittable { list.swipeUp() }
        XCTAssertTrue(dayAdd.isHittable)
    }

    @MainActor func testAddOpensDraftAndOnlySaveAttemptsMutation() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("静安\n")
        let add = app.buttons["add-search-place-demo-3"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["地点名称"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["当前为只读示例，连接服务后可添加地点。"].exists)
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts["当前为只读示例，连接服务后可添加地点。"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
    }

    @MainActor func testIPadRotationKeepsSearchAndSideBySideMap() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad layout")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let pin = app.buttons["map-search-result-demo-3"]
        XCTAssertTrue(pin.isHittable)
        XCTAssertLessThan(search.frame.maxX, app.windows.firstMatch.frame.width * 0.6)
        screenshot("iPad landscape search sidebar")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
        XCTAssertLessThan(search.frame.maxX, app.windows.firstMatch.frame.width * 0.6)
        XCTAssertTrue(pin.isHittable)
        screenshot("iPad portrait search sidebar")
        app.buttons["add-search-place-demo-3"].tap()
        let name = app.textFields["地点名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(pin.isHittable)
        name.tap(); name.typeText("测试")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue((name.value as? String)?.contains("测试") == true)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["放弃修改"].waitForExistence(timeout: 5))
        app.buttons["放弃修改"].tap()
        XCTAssertEqual(search.value as? String, "静安")
    }

    @MainActor func testToolbarSearchUsesPageScope() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom == .pad, "Phone toolbar")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let search = app.buttons["itinerary-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["itinerary-collapse"].exists)
        search.tap()
        XCTAssertTrue(app.staticTexts["搜索图标"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["同时添加到今日行程"].exists)
        app.buttons["close-place-picker"].tap()
        app.buttons["journey-back"].tap()
        search.tap()
        XCTAssertTrue(app.searchFields["map-place-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["同时添加到今日行程"].exists)
        app.buttons["close-place-picker"].tap()
        app.buttons["journey-back"].tap()
        search.tap()
        XCTAssertTrue(app.searchFields["map-place-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["同时添加到今日行程"].exists)
    }

    @MainActor private func openSearch(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        let add = app.buttons["day-search-add-place"]
        let list = app.collectionViews["itinerary-marker-list"]
        for _ in 0..<5 where !add.isHittable { list.swipeUp() }
        XCTAssertTrue(add.isHittable); add.tap()
        XCTAssertTrue(app.searchFields["map-place-search"].waitForExistence(timeout: 5))
    }
    @MainActor private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
