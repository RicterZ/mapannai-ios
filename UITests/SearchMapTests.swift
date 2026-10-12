import XCTest
import UIKit

final class SearchMapTests: XCTestCase {
    @MainActor func testSearchVisualReviewWithManyResults() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--search-visual-demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("咖啡\n")
        let first = app.buttons["add-place-result-visual-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-place-result-visual-5"].exists)
        screenshot("Search list with twelve fictional results")
        first.tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        sleep(2)
        XCTAssertFalse(app.staticTexts["地点笔记"].exists)
        XCTAssertFalse(app.staticTexts["已收藏"].exists)
        XCTAssertTrue(app.staticTexts["咖啡厅"].exists)
        screenshot("POI detail with supported fields only")
    }
    @MainActor func testSearchStyleAndSavedPlaceDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-marker:demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertLessThan(search.frame.minY, 160)
        XCTAssertFalse(app.buttons["compact-search-controls"].exists)
        screenshot("Full-page search without map background")
        result.tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        XCTAssertLessThan(app.buttons["search-detail-back"].frame.minY, 160)
        sleep(2)
        let panel = app.otherElements["edge-search-detail"]
        XCTAssertEqual(panel.frame.minX, app.windows.firstMatch.frame.minX, accuracy: 1)
        XCTAssertEqual(panel.frame.maxX, app.windows.firstMatch.frame.maxX, accuracy: 1)
        XCTAssertEqual(panel.frame.maxY, app.windows.firstMatch.frame.maxY, accuracy: 2)
        screenshot("Search result on map with half-height detail")
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(app.buttons["add-search-place-marker:demo-3"].exists)
        XCTAssertEqual(search.value as? String, "静安")
        app.buttons["close-place-picker"].tap()
        XCTAssertFalse(search.exists)
    }
    @MainActor func testFullPageUnsavedDetailAndDraftReturn() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--paged-search-demo"]; app.launch()
        openSearch(app)
        let search = app.searchFields["map-place-search"]
        search.tap(); search.typeText("咖啡\n")
        let result = app.buttons["add-place-result-paged-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let add = app.buttons["search-detail-add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["地点名称"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        app.buttons["search-detail-back"].tap()
        XCTAssertEqual(search.value as? String, "咖啡")
    }
    @MainActor func testArchiveSearchIsFullPageAndReturnsToTrip() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--archive-preview", "--trip-places-preview"]; app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let add = app.buttons["trip-add-place"]
        for _ in 0..<5 where !add.isHittable { app.swipeUp() }
        XCTAssertTrue(add.isHittable); add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertLessThan(search.frame.minY, 160)
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-marker:demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        screenshot("Full-page search from trip")
        result.tap()
        let back = app.buttons["search-detail-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertLessThan(back.frame.minY, 160)
        back.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["journey-edit-trip"].waitForExistence(timeout: 5))
    }
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
