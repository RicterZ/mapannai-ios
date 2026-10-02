import XCTest
import UIKit

final class NativeJourneyTests: XCTestCase {
    @MainActor func testIndependentMarkerHasDeleteMenuAndReturnsToOverview() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--overlapping-routes-demo"]
        app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap()
        app.buttons["journey-back"].tap()
        let row = app.buttons["independent-marker-demo-3"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["删除地点"].waitForExistence(timeout: 5))
        app.buttons["删除地点"].tap()
        XCTAssertTrue(app.alerts["删除地点？"].waitForExistence(timeout: 5))
        app.alerts["删除地点？"].buttons["取消"].tap()
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        app.buttons["close-marker-detail"].tap()
        XCTAssertTrue(app.navigationBars["我的旅途"].waitForExistence(timeout: 5))
        XCTAssertTrue(row.exists)
    }

    @MainActor func testMarkerDetailsRestoreJourneyDetent() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone native sheet")
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let panel = app.otherElements["phone-itinerary-panel"]
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        for expanded in [false, true] {
            if expanded {
                let bar = app.navigationBars["第1天"]
                let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -450)))
                let large = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 650 }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [large], timeout: 5), .completed)
            }
            let originalHeight = panel.frame.height
            row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
            XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
            let detailShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            detailShot.name = expanded ? "Place opened from full journey" : "Place opened from half journey"
            detailShot.lifetime = .keepAlways
            add(detailShot)
            app.buttons["close-marker-detail"].tap()
            let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                abs(panel.frame.height - originalHeight) < 10
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
            XCTAssertTrue(app.navigationBars["第1天"].exists)
            XCTAssertTrue(row.exists)
        }
    }

    @MainActor func testDistanceDividersPreservePlaceRowSpacing() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let first = app.buttons["route-0-marker-demo-1"], second = app.buttons["route-0-marker-demo-2"]
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        app.terminate()
        app.launchArguments = ["--demo", "--route-distance-preview"]; app.launch()
        XCTAssertTrue(second.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["850 m"].exists)
        XCTAssertTrue(app.staticTexts["1.2 km"].exists)
        let firstTitle = app.staticTexts["武康大楼"]
        let secondTitle = app.staticTexts["武康庭"]
        XCTAssertTrue(firstTitle.exists)
        XCTAssertTrue(secondTitle.exists)
        XCTAssertGreaterThan(app.staticTexts["850 m"].frame.midY, firstTitle.frame.midY)
        XCTAssertLessThan(app.staticTexts["850 m"].frame.midY, secondTitle.frame.midY)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Preview fixture — single distance divider and original spacing"
        shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor func testPlaceMenuAndRouteMenuStaySeparateAndEditorIsStandalone() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["从当天移除"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["删除路线"].exists)
        app.buttons["编辑路线"].tap()
        XCTAssertTrue(app.navigationBars["编辑路线"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route-save"].exists)
        app.buttons["取消"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        app.buttons["route-view-0"].press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["删除路线"].waitForExistence(timeout: 5))
        app.buttons["编辑路线"].tap()
        XCTAssertTrue(app.navigationBars["编辑路线"].waitForExistence(timeout: 5))
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["itinerary-search"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["编辑路线"].exists)
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
