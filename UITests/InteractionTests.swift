import XCTest
import UIKit

final class InteractionTests: XCTestCase {
    @MainActor func testTripDatesSettingsAndExistingMarkerDetail() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["trip-breadcrumb"].waitForExistence(timeout: 10))
        app.buttons["连接设置"].tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["API token（可留空）"].exists)
        XCTAssertFalse(app.secureTextFields["高德 iOS Key"].exists)
        app.buttons["close-settings"].tap()
        app.descendants(matching: .any).matching(identifier: "date-selector").firstMatch.tap()
        app.buttons["date-option-day-2"].tap()
        XCTAssertTrue(app.staticTexts["第2天"].waitForExistence(timeout: 5))
        app.descendants(matching: .any).matching(identifier: "date-selector").firstMatch.tap()
        app.buttons["date-option-day-1"].tap()
        let marker = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        let handle = app.buttons["itinerary-panel-toggle"]
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -350)))
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑地点"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["地点名称"].value as? String, "武康大楼")
        app.buttons["取消"].tap(); app.buttons["close-marker-detail"].tap()
        let back = app.buttons["journey-back"]
        let heading = app.otherElements["itinerary-panel-heading"]
        XCTAssertTrue(back.isHittable)
        XCTAssertLessThanOrEqual(back.frame.maxX, heading.frame.minX)
        XCTAssertLessThan(back.frame.midY, app.textFields["搜索地点"].frame.minY)
        back.tap()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["date-selector"].exists)
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.staticTexts["旅途"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["journey-back"].exists)
    }
    @MainActor func testRouteEditorAndTripCreationForms() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["新建路线"].waitForExistence(timeout: 10))
        app.scrollViews["itinerary-marker-list"].swipeUp()
        app.buttons["新建路线"].tap()
        XCTAssertTrue(app.navigationBars["新建路线"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        XCTAssertFalse(app.buttons["chain-add-marker-demo-3"].exists)
        app.buttons["chain-add-marker-demo-0"].tap()
        app.buttons["chain-add-marker-demo-1"].tap()
        XCTAssertTrue(app.buttons["保存"].isEnabled)
        app.buttons["取消"].tap()
        app.buttons["trip-breadcrumb"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        app.buttons["exit-journey"].tap()
        let list = app.scrollViews["itinerary-marker-list"]
        list.swipeDown()
        XCTAssertTrue(app.buttons["create-journey"].waitForExistence(timeout: 5))
        app.buttons["create-journey"].tap()
        XCTAssertTrue(app.navigationBars["创建旅行"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["旅行名称"].exists)
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["journey-demo-trip"].exists)
        let overviewImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); overviewImage.name = "Journey overview"; overviewImage.lifetime = .keepAlways; add(overviewImage)
        XCTAssertFalse(app.buttons["trip-breadcrumb"].exists)
        list.swipeUp()
        app.buttons["journey-demo-trip"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        let daysImage = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); daysImage.name = "Journey days"; daysImage.lifetime = .keepAlways; add(daysImage)
        app.buttons["journey-day-day-1"].tap()
        XCTAssertTrue(app.buttons["route-toggle-0"].waitForExistence(timeout: 5))
    }
    @MainActor func testAddingPlacesSearchAndMapSelection() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let handle = app.buttons["itinerary-panel-toggle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -350)))
        app.scrollViews["itinerary-marker-list"].swipeUp()
        app.buttons["加入地点"].tap()
        XCTAssertTrue(app.textFields["saved-place-query"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["day-add-place-demo-3"].exists)
        let query = app.textFields["saved-place-query"]
        query.tap(); query.typeText("静安")
        XCTAssertTrue(app.buttons["day-add-place-demo-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["day-add-place-demo-0"].exists)
        app.buttons["清除搜索"].tap()
        app.buttons["choose-place-on-map"].tap()
        XCTAssertFalse(app.textFields["saved-place-query"].exists)
        handle.tap()
        app.buttons["map-marker-demo-3"].tap()
        XCTAssertTrue(app.buttons["add-marker-to-current-day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-marker-to-current-day"].isEnabled)
        app.buttons["close-marker-detail"].tap()
    }

}
final class IPadLayoutTests: XCTestCase {
    @MainActor func testLandscapeSidebarAndPortraitTransition() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "This layout test requires an iPad")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let sidebar = app.otherElements["landscape-itinerary-sidebar"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 10))
        let window = app.windows.element(boundBy: 0)
        XCTAssertGreaterThan(window.frame.width, window.frame.height)
        XCTAssertLessThan(sidebar.frame.width, window.frame.width * 0.5)
        XCTAssertLessThan(sidebar.frame.maxX, window.frame.width * 0.5)
        XCTAssertEqual(sidebar.frame.minX, window.frame.minX, accuracy: 1)
        XCTAssertEqual(sidebar.frame.minY, window.frame.minY, accuracy: 1)
        XCTAssertEqual(sidebar.frame.maxY, window.frame.maxY, accuracy: 1)
        let heading = app.otherElements["itinerary-panel-heading"]
        let dayTitle = heading.staticTexts["第1天"]
        let dayDate = heading.staticTexts["10月1日"]
        XCTAssertTrue(dayTitle.exists)
        XCTAssertTrue(dayDate.exists)
        XCTAssertGreaterThan(dayDate.frame.minX, dayTitle.frame.maxX)
        XCTAssertEqual(dayTitle.frame.midY, dayDate.frame.midY, accuracy: 8)
        let search = app.textFields["搜索地点"]
        XCTAssertGreaterThanOrEqual(search.frame.minX, sidebar.frame.minX)
        XCTAssertLessThanOrEqual(search.frame.maxX, sidebar.frame.maxX)
        let location = app.buttons["定位到当前位置"]
        XCTAssertGreaterThan(location.frame.minX, window.frame.width * 0.8)
        XCTAssertGreaterThan(location.frame.minY, window.frame.height * 0.8)
        XCTAssertLessThan(location.frame.maxY, window.frame.maxY - 15)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); screenshot.name = "iPad landscape"; screenshot.lifetime = .keepAlways
        add(screenshot)
        let collapse = app.buttons["itinerary-panel-toggle"]
        let dragStart = collapse.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).withOffset(CGVector(dx: -70, dy: 0))
        dragStart.press(forDuration: 0.1, thenDragTo: dragStart.withOffset(CGVector(dx: -170, dy: 0)))
        XCTAssertTrue(app.buttons["展开行程"].waitForExistence(timeout: 5))
        app.buttons["展开行程"].tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        app.buttons["连接设置"].tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields["高德 iOS Key"].exists)
        app.buttons["close-settings"].tap()
        XCUIDevice.shared.orientation = .portrait
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: sidebar)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(app.buttons["itinerary-panel-toggle"].exists)
    }
}
final class PhonePanelTests: XCTestCase {
    @MainActor func testPanelTouchesBottomAndSupportsDraggingInBothDirections() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let panel = app.descendants(matching: .any).matching(identifier: "phone-itinerary-panel").firstMatch
        let handle = app.descendants(matching: .any).matching(identifier: "itinerary-panel-toggle").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 10))
        let window = app.windows.element(boundBy: 0)
        XCTAssertEqual(panel.frame.maxY, window.frame.maxY, accuracy: 2)
        let heading = app.otherElements["itinerary-panel-heading"]
        let dayTitle = heading.staticTexts["第1天"]
        let dayDate = heading.staticTexts["10月1日"]
        XCTAssertTrue(dayTitle.exists)
        XCTAssertTrue(dayDate.exists)
        XCTAssertGreaterThan(dayDate.frame.minX, dayTitle.frame.maxX)
        XCTAssertEqual(dayTitle.frame.midY, dayDate.frame.midY, accuracy: 8)
        let search = app.textFields["搜索地点"]
        XCTAssertGreaterThan(search.frame.minY, panel.frame.minY)
        XCTAssertLessThan(search.frame.maxY, panel.frame.maxY)
        XCTAssertTrue(panel.descendants(matching: .button).matching(identifier: "连接设置").firstMatch.exists)
        XCTAssertTrue(app.staticTexts["第1天"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "拖动展开")).firstMatch.exists)
        XCTAssertFalse(app.buttons["返回地图"].exists)
        let half = panel.frame.height
        addScreenshot(app, name: "iPhone half panel")
        handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).withOffset(CGVector(dx:0,dy:260)))
        let collapsed = NSPredicate { _, _ in panel.frame.height < half * 0.6 }
        expectation(for: collapsed, evaluatedWith: panel); waitForExpectations(timeout: 5)
        XCTAssertEqual(panel.frame.maxY,window.frame.maxY,accuracy:2)
        let compactHeight = panel.frame.height
        addScreenshot(app, name: "iPhone collapsed panel")
        handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).withOffset(CGVector(dx:0,dy:-280)))
        let opened = NSPredicate { _, _ in panel.frame.height > compactHeight * 1.8 }
        expectation(for: opened,evaluatedWith:panel);waitForExpectations(timeout:5)
        handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).press(forDuration: 0.1, thenDragTo: handle.coordinate(withNormalizedOffset: CGVector(dx:0.15,dy:0.5)).withOffset(CGVector(dx:0,dy:-250)))
        let full = NSPredicate { _, _ in panel.frame.height > half + 100 }
        expectation(for: full,evaluatedWith:panel);waitForExpectations(timeout:5)
        XCTAssertEqual(panel.frame.maxY,window.frame.maxY,accuracy:2)
        XCTAssertEqual(panel.frame.minY, window.frame.minY, accuracy: 2)
        XCTAssertFalse(app.buttons["定位到当前位置"].exists)
        XCTAssertFalse(app.buttons["trip-breadcrumb"].exists)
        XCTAssertTrue(app.buttons["route-0-marker-demo-0"].isHittable)
        addScreenshot(app, name: "iPhone expanded panel")
        let down = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.75))
        down.press(forDuration: 0.1, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 400)))
        let returned = NSPredicate { _, _ in panel.frame.height < window.frame.height * 0.7 }
        expectation(for: returned, evaluatedWith: panel); waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["trip-breadcrumb"].exists)
    }
    private func addScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }
}

final class RouteSettingsTests: XCTestCase {
    @MainActor func testPlanningIsOnlyInSettingsWithAutomaticMode() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["连接设置"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.switches["planning-toggle"].exists)
        XCTAssertFalse(app.segmentedControls["route-mode-picker"].exists)
        app.buttons["连接设置"].tap()
        let toggle = app.switches["planning-toggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        if toggle.value as? String != "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let modes = app.segmentedControls["route-mode-picker"]
        XCTAssertTrue(modes.waitForExistence(timeout: 5))
        modes.buttons["自动"].tap()
        XCTAssertTrue(modes.buttons["自动"].isSelected)
        modes.buttons["步行"].tap()
        if toggle.value as? String == "1" { toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        app.buttons["close-settings"].tap()
        XCTAssertFalse(app.switches["planning-toggle"].exists)
        XCTAssertFalse(app.segmentedControls["route-mode-picker"].exists)
    }
}

final class NativeGestureTests: XCTestCase {
    @MainActor func testCenteredBreadcrumbAndRouteLongPressMenu() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let nav = app.otherElements["journey-navigation"]
        XCTAssertTrue(nav.waitForExistence(timeout: 10))
        XCTAssertEqual(nav.frame.midX, app.windows.firstMatch.frame.midX, accuracy: 2)
        XCTAssertFalse(app.switches["编辑"].exists)
        app.buttons["date-selector"].tap()
        let dropdown = app.scrollViews["date-dropdown"]
        XCTAssertTrue(dropdown.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(dropdown.frame.width, 200)
        XCTAssertTrue(app.buttons["date-option-day-2"].staticTexts["第2天"].exists)
        XCTAssertTrue(app.buttons["date-option-day-2"].staticTexts["10月2日"].exists)
        app.buttons["date-option-day-2"].tap()
        XCTAssertTrue(app.staticTexts["第2天"].exists)
        app.buttons["date-selector"].tap(); app.buttons["date-option-day-1"].tap()
        let handle = app.buttons["itinerary-panel-toggle"]
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -350)))
        app.buttons["route-toggle-0"].press(forDuration: 1)
        XCTAssertTrue(app.buttons["编辑顺序"].waitForExistence(timeout: 5))
        app.buttons["编辑顺序"].tap()
        XCTAssertTrue(app.navigationBars["编辑路线"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }
}

final class MapSetupTests: XCTestCase {
    @MainActor func testConnectionPromptIsBelowDisabledMapAndOpensSettings() {
        let app = XCUIApplication(); app.launch()
        let placeholder = app.otherElements["map-setup-placeholder"]
        XCTAssertTrue(placeholder.waitForExistence(timeout: 10))
        let title = placeholder.staticTexts["地图未开启"]
        let prompt = placeholder.staticTexts["连接服务以查看地点和行程。"]
        let connect = placeholder.buttons["连接我的服务"]
        XCTAssertTrue(title.exists)
        XCTAssertTrue(prompt.exists)
        XCTAssertTrue(connect.exists)
        XCTAssertGreaterThan(prompt.frame.minY, title.frame.maxY)
        XCTAssertGreaterThan(connect.frame.minY, prompt.frame.maxY)
        XCTAssertFalse(app.otherElements["landscape-itinerary-sidebar"].buttons["连接我的服务"].exists)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Map setup connection"; screenshot.lifetime = .keepAlways; add(screenshot)
        connect.tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
    }
}

final class MarkerPresentationTests: XCTestCase {
    @MainActor func testEmptyNoteIsCompactAndMapRemainsSelectable() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Map interaction behind a sheet is checked in landscape")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let first = app.buttons["map-marker-demo-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["marker-note"].exists)
        let emptyScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        emptyScreenshot.name = "Compact empty-note details"; emptyScreenshot.lifetime = .keepAlways; add(emptyScreenshot)
        let another = app.buttons["map-marker-demo-4"]
        XCTAssertTrue(another.isHittable)
        another.tap()
        XCTAssertTrue(app.staticTexts["愚园路"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Undimmed marker details"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
