import XCTest
import UIKit

final class NativeJourneyTests: XCTestCase {
    @MainActor func testLongPressDragsInPlaceAndRetainsEditModeUntilCancel() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let first = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        let second = app.buttons["route-0-marker-demo-2"]
        XCTAssertTrue(second.exists)
        first.press(forDuration: 0.5, thenDragTo: second)
        let save = app.buttons["route-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["route-remove-demo-1"].exists)
        XCTAssertFalse(app.buttons["itinerary-search"].exists)
        XCTAssertFalse(app.buttons["itinerary-header-location"].exists)
        XCTAssertFalse(app.alerts["删除路线？"].exists)
        XCTAssertGreaterThan(first.frame.midY, second.frame.midY)
        app.buttons["route-remove-demo-2"].tap()
        XCTAssertFalse(second.exists)
        XCTAssertTrue(save.exists)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Inline route edit after dragging"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["route-cancel"].tap()
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["itinerary-search"].exists)
        XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
        XCTAssertFalse(save.exists)
        XCTAssertLessThan(first.frame.midY, second.frame.midY)
    }
    @MainActor func testUnchangedInlineSaveRestoresToolsAndPlaceTap() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 0.5)
        let save = app.buttons["route-save"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()
        XCTAssertTrue(app.buttons["itinerary-search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
        XCTAssertFalse(save.exists)
        row.tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
    }
    @MainActor func testRepeatedCompactExpansionPreservesAllJourneyScopes() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone native sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let panel = app.otherElements["phone-itinerary-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        for title in ["第1天", "上海 · 秋日散步", "我的旅途"] {
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 5))
            for _ in 0..<2 {
                let down = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                down.press(forDuration: 0.1, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 500)))
                let controls = app.otherElements["compact-journey-controls"]
                XCTAssertTrue(controls.waitForExistence(timeout: 5))
                XCTAssertEqual(app.buttons["itinerary-header-location"].frame.midY, controls.frame.midY, accuracy: 2)
                let up = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
                up.press(forDuration: 0.1, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -300)))
                let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    panel.frame.height > 300 && !controls.exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
                XCTAssertTrue(bar.exists)
                XCTAssertTrue(app.collectionViews["itinerary-marker-list"].exists)
                let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                attachment.name = "Expanded \(title)"; attachment.lifetime = .keepAlways; add(attachment)
            }
            if title != "我的旅途" { app.buttons["journey-back"].tap() }
        }
    }

    @MainActor func testSystemJourneySheetNavigationDraggingAndNestedPlaceDetails() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone native sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let panel = app.otherElements["phone-itinerary-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let title = app.staticTexts["itinerary-panel-title"]
        XCTAssertEqual(title.label, "第1天")
        XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
        XCTAssertFalse(app.buttons["date-selector"].exists)
        let down = app.navigationBars["第1天"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        down.press(forDuration: 0.1, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 500)))
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height < 200 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
        let dateSelector = app.buttons["date-selector"]
        XCTAssertTrue(dateSelector.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(dateSelector.frame.minY, panel.frame.minY - 1)
        XCTAssertEqual(app.buttons["itinerary-header-location"].frame.midY, app.otherElements["compact-journey-controls"].frame.midY, accuracy: 2)
        dateSelector.tap()
        XCTAssertTrue(app.buttons["date-option-day-1"].waitForExistence(timeout: 5))
        app.buttons["date-option-day-1"].tap()
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "Collapsed two-row journey navigation"; compact.lifetime = .keepAlways; add(compact)
        let up = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        up.press(forDuration: 0.1, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -300)))
        let medium = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 300 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [medium], timeout: 5), .completed)
        XCTAssertFalse(app.buttons["date-selector"].exists)
        let bar = app.navigationBars["第1天"]
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: -450)))
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 650 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        let large = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        large.name = "Native journey large sheet"; large.lifetime = .keepAlways; add(large)
        app.buttons["route-0-marker-demo-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["marker-navigate"].exists)
        XCTAssertTrue(app.buttons["marker-delete"].exists)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "marker-note").firstMatch.waitForExistence(timeout: 5))
        app.buttons["close-marker-detail"].tap()
        XCTAssertTrue(app.buttons["itinerary-header-location"].waitForExistence(timeout: 5))
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Native journey toolbar and days"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["journey-back"].tap()
        app.buttons["create-journey"].tap()
        XCTAssertTrue(app.navigationBars["创建旅行"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }
}
