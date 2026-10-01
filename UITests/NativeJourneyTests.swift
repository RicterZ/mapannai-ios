import XCTest
import UIKit

final class NativeJourneyTests: XCTestCase {
    @MainActor func testSystemJourneySheetNavigationDraggingAndNestedPlaceDetails() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone native sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let panel = app.otherElements["phone-itinerary-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        let title = app.staticTexts["itinerary-panel-title"]
        XCTAssertEqual(title.label, "第1天")
        XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
        let down = app.navigationBars["第1天"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        down.press(forDuration: 0.1, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 500)))
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height < 200 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
        let up = app.navigationBars["第1天"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        up.press(forDuration: 0.1, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -300)))
        let medium = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 300 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [medium], timeout: 5), .completed)
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
