import XCTest
import UIKit

final class IPadDetailTests: XCTestCase {
    @MainActor func testMarkerDetailsAreAlwaysExpandedAndCannotResize() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Fixed iPad detail dialog")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let marker = app.buttons["map-marker-demo-0"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10)); marker.tap()
        let bar = app.navigationBars["地点"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch
        XCTAssertEqual(bar.frame.midX, window.frame.midX, accuracy: 2)
        XCTAssertLessThan(bar.frame.minY, window.frame.height * 0.2)
        XCTAssertTrue(app.buttons["marker-itinerary-day-1"].exists)
        let initial = bar.frame
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 200)))
        XCTAssertTrue(bar.exists); XCTAssertEqual(bar.frame, initial)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Fixed expanded iPad details"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["close-marker-detail"].tap()
    }
}
