import XCTest
import UIKit

final class LongPressPresentationTests: XCTestCase {
    @MainActor func testLongPressStartsAtHalfScreenAndCanExpand() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone detents")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let collapse = app.buttons["itinerary-collapse"]
        XCTAssertTrue(collapse.waitForExistence(timeout: 10))
        let locate = app.buttons["itinerary-header-location"]
        XCTAssertEqual(collapse.frame.midY, locate.frame.midY, accuracy: 1)
        collapse.tap()
        XCTAssertFalse(app.buttons["create-journey"].exists)
        XCTAssertLessThanOrEqual(collapse.frame.width, 52)
        XCTAssertLessThanOrEqual(locate.frame.width, 52)
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "Compact journey native toolbar"; compact.lifetime = .keepAlways; add(compact)
        let map = app.otherElements["preview-map-surface"]
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).press(forDuration: 1)
        let bar = app.navigationBars["添加地点"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(bar.frame.minY, app.frame.height * 0.35)
        XCTAssertLessThan(bar.frame.minY, app.frame.height * 0.65)
        let medium = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        medium.name = "Long press medium sheet"; medium.lifetime = .keepAlways; add(medium)
        let handle = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -450)))
        let expanded = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in bar.frame.minY < 150 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expanded], timeout: 5), .completed)
        app.buttons["取消"].tap()
    }
}
