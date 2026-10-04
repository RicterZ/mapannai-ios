import XCTest
final class POIScreenshotTests: XCTestCase {
    @MainActor func testCaptureNativeSelectionFresh() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let back = app.buttons["journey-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap(); back.tap()
        let settings = app.buttons["itinerary-settings-bottom"]
        if !settings.isHittable { app.collectionViews["itinerary-marker-list"].swipeUp() }
        settings.tap(); app.buttons["map-renderer-picker"].tap(); app.buttons["系统地图"].tap(); app.buttons["close-settings"].tap()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        let poi = map.otherElements.matching(NSPredicate(format: "label CONTAINS %@", "静安寺")).firstMatch
        XCTAssertTrue(poi.waitForExistence(timeout: 5)); poi.tap()
        XCTAssertTrue(app.navigationBars["添加地点"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); shot.name = "System map native POI selected"; shot.lifetime = .keepAlways; add(shot)
    }
}
