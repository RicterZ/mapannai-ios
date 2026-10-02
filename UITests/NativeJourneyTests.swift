import XCTest
import UIKit

final class NativeJourneyTests: XCTestCase {
    @MainActor func testOfflineRouteSecondToThirdKeepsUniqueRowsAndNumbers() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview"]
        app.launch()
        let source = app.buttons["trip-unscheduled-preview-cafe"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        let target = app.buttons["journey-day-day-1"]
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 1)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !source.exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        target.tap()
        let isolated = app.buttons["day-marker-preview-cafe"]
        if !isolated.waitForExistence(timeout: 3) { app.swipeUp() }
        XCTAssertTrue(isolated.waitForExistence(timeout: 5))
        let route = app.buttons["route-0-marker-demo-1"]
        if !route.isHittable { app.swipeDown() }
        isolated.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: route.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.2)),
            withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["route-0-marker-preview-cafe"].waitForExistence(timeout: 5))
        XCTAssertFalse(isolated.exists)
        let inserted = app.buttons["route-0-marker-preview-cafe"]
        XCTAssertLessThan(inserted.frame.minY, app.buttons["route-0-marker-demo-1"].frame.minY)
        XCTAssertGreaterThan(inserted.frame.minY, app.buttons["route-0-marker-demo-0"].frame.minY)
        XCTAssertEqual(inserted.value as? String, "2")
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-preview-cafe").count, 1)
        let next = app.buttons["route-0-marker-demo-1"]
        inserted.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: next.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.8)),
            withVelocity: .slow, thenHoldForDuration: 0.2)
        XCTAssertEqual(inserted.value as? String, "3")
        XCTAssertEqual(next.value as? String, "2")
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-preview-cafe").count, 1)
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-demo-1").count, 1)
        let last = app.buttons["route-0-marker-demo-0"]
        inserted.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: last.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.1)),
            withVelocity: .slow, thenHoldForDuration: 1)
        let reordered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            inserted.frame.minY < last.frame.minY
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [reordered], timeout: 5), .completed)
        let finalRow = app.buttons["route-0-marker-demo-2"]
        inserted.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: finalRow.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.8)),
            withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertGreaterThan(inserted.frame.minY, app.buttons["route-0-marker-demo-1"].frame.minY)
        XCTAssertGreaterThan(inserted.frame.minY, finalRow.frame.minY)
        XCTAssertEqual(inserted.value as? String, "4")
        XCTAssertEqual(app.buttons["route-0-marker-demo-1"].value as? String, "2")
        XCTAssertEqual(finalRow.value as? String, "3")
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-preview-cafe").count, 1)
        let pool = app.buttons["day-search-add-place"]
        if !pool.isHittable { app.swipeUp() }
        inserted.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)).press(
            forDuration: 1.5, thenDragTo: pool.coordinate(withNormalizedOffset: CGVector(dx: 0.35, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["day-marker-preview-cafe"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route-0-marker-preview-cafe"].exists)
        XCTAssertTrue(app.buttons["route-0-marker-demo-0"].exists)
        XCTAssertTrue(app.buttons["route-0-marker-demo-1"].exists)
    }

    @MainActor func testMapLongPressReplacesDetailWithEditorAndCancelKeepsJourneyCompact() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.2)).press(forDuration: 1)
        XCTAssertTrue(app.navigationBars["添加地点"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["close-marker-detail"].exists)
        app.buttons["取消"].tap()
        let panel = app.otherElements["phone-itinerary-panel"]
        let compact = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height < 200 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [compact], timeout: 5), .completed)
        XCTAssertFalse(app.navigationBars["地点"].exists)
    }

    @MainActor func testSwitchingCompactAndNoteDetailsResizesSameSheet() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let first = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let bar = app.navigationBars["地点"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let compactY = bar.frame.minY
        let next = app.buttons["map-marker-demo-1"]
        XCTAssertTrue(next.isHittable); next.tap()
        XCTAssertTrue(app.staticTexts["武康庭"].waitForExistence(timeout: 5))
        let resized = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bar.frame.minY < compactY - 20 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [resized], timeout: 5), .completed)
        XCTAssertGreaterThan(bar.frame.minY, 200)
        app.buttons["close-marker-detail"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
    }

    @MainActor func testSwitchingCoverDetailsGrowsAndShrinksSameSheet() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--cover-resize-preview"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        let bar = app.navigationBars["地点"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let originalY = bar.frame.minY
        app.buttons["map-marker-demo-2"].tap()
        let taller = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bar.frame.minY < originalY - 80 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [taller], timeout: 5), .completed)
        app.buttons["map-marker-demo-1"].tap()
        let shorter = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(bar.frame.minY - originalY) < 5 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [shorter], timeout: 5), .completed)
        app.buttons["close-marker-detail"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
    }

    @MainActor func testSwitchingMapMarkerKeepsDetailHalfScreenAndJourneyReturnHeight() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let panel = app.otherElements["phone-itinerary-panel"]
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        let bar = app.navigationBars["第1天"]
        let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -450)))
        let large = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 650 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [large], timeout: 5), .completed)
        let originalHeight = panel.frame.height
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["close-marker-detail"].waitForExistence(timeout: 5))
        let detailBar = app.navigationBars["地点"]
        let previousY = detailBar.frame.minY
        let other = app.buttons["map-marker-demo-2"]
        XCTAssertTrue(other.isHittable)
        other.tap()
        XCTAssertTrue(app.staticTexts["安福路"].waitForExistence(timeout: 5))
        XCTAssertEqual(detailBar.frame.minY, previousY, accuracy: 15)
        app.buttons["close-marker-detail"].tap()
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(panel.frame.height - originalHeight) < 10 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
    }

    @MainActor func testCoverPlaceholderIsCenteredInBanner() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10)); row.tap()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5)); app.buttons["编辑"].tap()
        let cover = app.buttons["marker-cover-upload"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5))
        if !cover.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertEqual(cover.frame.width / cover.frame.height, 16.0 / 9.0, accuracy: 0.05)
        let label = app.staticTexts["添加封面图"]
        XCTAssertTrue(label.exists)
        XCTAssertEqual(label.frame.midY, cover.frame.midY, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Centered cover banner placeholder"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    @MainActor func testLongNoteExpandsAndScrollsWithWholeDetail() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--long-note-preview"]; app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        XCTAssertTrue(app.navigationBars["地点"].waitForExistence(timeout: 5))
        let web = app.webViews.firstMatch
        XCTAssertTrue(web.waitForExistence(timeout: 5))
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in web.frame.height > 500 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        let end = web.staticTexts["长笔记结束"]
        for _ in 0..<14 {
            if end.exists && end.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(end.exists)
        XCTAssertTrue(end.isHittable)
    }

    @MainActor func testDeleteChainConfirmationActuallySubmitsDeletion() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let route = app.buttons["route-view-0"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        route.press(forDuration: 0.7)
        app.buttons["删除路线"].tap()
        XCTAssertTrue(app.alerts["删除路线？"].waitForExistence(timeout: 5))
        app.alerts["删除路线？"].buttons["删除"].tap()
        // Read-only mode must reach the store and reject the write, not silently skip it.
        XCTAssertTrue(app.alerts["无法完成操作"].waitForExistence(timeout: 5))
        XCTAssertTrue(route.exists)
    }

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
