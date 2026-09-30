import XCTest
import UIKit

final class JourneyTitleTests: XCTestCase {
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
                app.buttons["itinerary-collapse"].tap()
                XCTAssertEqual(title.frame.midX, container.frame.midX, accuracy: 3)
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
