import XCTest
import UIKit

final class JourneyTitleTests: XCTestCase {
    @MainActor func testMarkerDetailsPreserveCollapsedJourney() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("Phone sheet regression") }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 500)))
        let location = app.buttons["itinerary-header-location"]
        let originalY = location.frame.midY
        XCTAssertGreaterThan(originalY, app.frame.height * 0.8)
        let marker = app.buttons["map-marker-demo-0"]
        XCTAssertTrue(marker.isHittable); marker.tap()
        let close = app.buttons["close-marker-detail"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertLessThan(marker.frame.maxY, app.navigationBars["地点"].frame.minY)
        close.tap()
        XCTAssertTrue(location.waitForExistence(timeout: 5))
        XCTAssertEqual(location.frame.midY, originalY, accuracy: 3)
    }
    @MainActor func testPopKeepsToolbarVerticalPosition() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let back = app.buttons["journey-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap()
        let title = app.staticTexts["itinerary-panel-title"]
        let trip = NSPredicate(format: "label == %@", "上海 · 秋日散步")
        expectation(for: trip, evaluatedWith: title); waitForExpectations(timeout: 5)
        let toggle = app.buttons[UIDevice.current.userInterfaceIdiom == .pad ? "itinerary-panel-toggle" : "itinerary-search"]
        let titleY = title.frame.midY, buttonY = toggle.frame.midY
        back.tap()
        expectation(for: NSPredicate(format: "label == %@", "旅途"), evaluatedWith: title)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(title.frame.midY, titleY, accuracy: 1)
        XCTAssertEqual(toggle.frame.midY, buttonY, accuracy: 1)
        XCTAssertTrue(app.buttons["create-journey"].exists)
    }
    @MainActor func testLongAndShortTitlesStayAtContainerCenter() throws {
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        for longTitle in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = longTitle ? ["--demo", "--long-title-demo"] : ["--demo"]
            app.launch()
            XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
            app.buttons["journey-back"].tap()
            let title = app.staticTexts["itinerary-panel-title"]
            let expected = longTitle ? "呼和浩特·大同美食行" : "上海 · 秋日散步"
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: title)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
            let container = UIDevice.current.userInterfaceIdiom == .pad
                ? app.otherElements["landscape-itinerary-sidebar"] : app.otherElements["phone-itinerary-panel"]
            XCTAssertEqual(title.frame.midX, container.frame.midX, accuracy: 3)
            if UIDevice.current.userInterfaceIdiom == .phone {
                let bar = app.navigationBars.firstMatch
                let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
                drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 500)))
                XCTAssertEqual(title.frame.midX, container.frame.midX, accuracy: 3)
                // Buttons move up four points; the compact title moves up two points.
                XCTAssertEqual(title.frame.midY - app.buttons["itinerary-header-location"].frame.midY, 2, accuracy: 1.5)
                let left = app.buttons["journey-back"]
                let right = app.buttons["itinerary-header-location"]
                XCTAssertGreaterThanOrEqual(title.frame.minX, left.frame.maxX)
                XCTAssertLessThanOrEqual(title.frame.maxX, right.frame.minX)
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = longTitle ? "Centered long trip title" : "Centered short trip title"
            shot.lifetime = .keepAlways; add(shot)
            app.terminate()
        }
    }
}
