import XCTest

final class MapBackgroundTests: XCTestCase {
    @MainActor func testAppleBackgroundSwitchAndReturnToAMap() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let back = app.buttons["journey-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap(); back.tap()
        let settings = app.buttons["itinerary-settings-bottom"]
        if !settings.isHittable { app.collectionViews["itinerary-marker-list"].swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        let picker = app.buttons["map-renderer-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        app.buttons["系统地图"].tap()
        app.buttons["close-settings"].tap()
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        settings.tap(); picker.tap(); app.buttons["Google 地图"].tap()
        app.buttons["close-settings"].tap()
        // Empty Google key must quietly keep a usable native system map.
        XCTAssertTrue(app.maps.firstMatch.waitForExistence(timeout: 10))
        settings.tap(); picker.tap(); app.buttons["高德地图"].tap()
        app.buttons["close-settings"].tap()
        XCTAssertFalse(app.maps.firstMatch.exists)
    }
}
