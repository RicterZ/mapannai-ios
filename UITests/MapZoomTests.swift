import XCTest

final class MapZoomTests: XCTestCase {
    @MainActor func testDotsExpandWhenZoomingAndYearSeparatorIsCompact() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--compact-map-demo"]; app.launch()
        let marker = app.buttons["map-marker-demo-3"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        XCTAssertEqual(marker.value as? String, "圆点")
        let compact = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        compact.name = "Dots without connection lines"; compact.lifetime = .keepAlways; add(compact)
        let map = app.otherElements["preview-map-surface"]
        map.pinch(withScale: 3, velocity: 1)
        let expanded = NSPredicate { _, _ in marker.value as? String == "图标" }
        expectation(for: expanded, evaluatedWith: marker); waitForExpectations(timeout: 5)
        let detailed = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detailed.name = "Expanded icons with restored routes"; detailed.lifetime = .keepAlways; add(detailed)
        app.buttons["exit-journey"].tap()
        let year = app.descendants(matching: .any).matching(identifier: "journey-year-2026").firstMatch
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        XCTAssertLessThan(year.frame.height, 35)
        let overview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        overview.name = "Compact year divider"; overview.lifetime = .keepAlways; add(overview)
    }
}
