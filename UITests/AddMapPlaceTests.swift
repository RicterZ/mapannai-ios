import XCTest
import UIKit

final class AddMapPlaceTests: XCTestCase {
    @MainActor func testDayUsesMapSearchAndSettingsAreAtBottom() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let list = app.collectionViews["itinerary-marker-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .phone {
            let bar = app.navigationBars["第1天"]
            let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: -450)))
        }
        XCTAssertFalse(app.searchFields["map-place-search"].exists)
        XCTAssertFalse(app.staticTexts["未安排"].exists)
        let addPlace = app.buttons["添加地点"]
        for _ in 0..<4 where !addPlace.isHittable { list.swipeUp() }
        XCTAssertTrue(addPlace.isHittable)
        let settings = app.buttons["itinerary-settings-bottom"]
        for _ in 0..<3 where !settings.isHittable { list.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        app.buttons["close-settings"].tap()
        for _ in 0..<3 where !addPlace.isHittable { list.swipeDown() }
        addPlace.tap()
        XCTAssertTrue(app.navigationBars["添加地点"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["choose-place-on-map"].exists)
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("武康\n")
        let result = app.buttons["add-place-result-demo-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertEqual(app.textFields["地点名称"].value as? String, "武康大楼")
        XCTAssertTrue(app.buttons["保存"].exists)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "Map search selected place editor"; image.lifetime = .keepAlways; add(image)
        app.buttons["取消"].tap()
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        if !app.buttons["close-place-picker"].exists { app.buttons["Close"].tap() }
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["添加地点"].waitForExistence(timeout: 5))
    }
}
