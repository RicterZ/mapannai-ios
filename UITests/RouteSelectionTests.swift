import XCTest

final class RouteSelectionTests: XCTestCase {
    @MainActor func testLineClickOpensDayAtHalfHeightAndRepeats() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap()
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 500)))
        let map = app.otherElements["preview-map-surface"]
        let a = app.buttons["map-marker-demo-0"], b = app.buttons["map-marker-demo-1"]
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        let target = CGPoint(x: (a.frame.midX + b.frame.midX) / 2, y: (a.frame.midY + b.frame.midY) / 2)
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.x - map.frame.minX, dy: target.y - map.frame.minY)).tap()
        XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        let panel = app.otherElements["phone-itinerary-panel"]
        let medium = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height > 300 && panel.frame.height < 650 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [medium], timeout: 5), .completed)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Selected day route and half sheet"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["journey-back"].tap()
        let collapsed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in panel.frame.height < 180 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [collapsed], timeout: 5), .completed)
    }
    @MainActor func testOverlappingRoutesShowDayChoicesAtTapWithoutMovingMap() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--overlapping-routes-demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap()
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 500)))
        let map = app.otherElements["preview-map-surface"]
        let a = app.buttons["map-marker-demo-0"], b = app.buttons["map-marker-demo-1"]
        XCTAssertTrue(a.waitForExistence(timeout: 5))
        let target = CGPoint(x: (a.frame.midX + b.frame.midX) / 2, y: (a.frame.midY + b.frame.midY) / 2)
        map.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: target.x - map.frame.minX, dy: target.y - map.frame.minY)).tap()
        let first = app.buttons["route-day-choice-day-1"], second = app.buttons["route-day-choice-day-2"]
        XCTAssertTrue(first.waitForExistence(timeout: 2))
        XCTAssertEqual(first.label, "第1天")
        XCTAssertEqual(second.label, "第2天")
        XCTAssertLessThan(abs(first.frame.midX - target.x), 120)
        XCTAssertLessThan(abs(second.frame.midY - target.y), 150)
        XCTAssertLessThan(second.frame.maxY, target.y - 5, "The menu must sit above the actual tap, without a safe-area offset")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Day choices anchored to route tap"; attachment.lifetime = .keepAlways; add(attachment)
        second.tap()
        XCTAssertTrue(app.navigationBars["第2天"].waitForExistence(timeout: 5))
        XCTAssertFalse(first.exists)
    }

}
