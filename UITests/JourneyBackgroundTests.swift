import XCTest
import UIKit

final class JourneyBackgroundTests: XCTestCase {
    @MainActor func testSettingsOnlyAtOverviewBottomAcrossNativeSheetPages() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let list = app.collectionViews["itinerary-marker-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let settings = app.buttons["itinerary-settings-bottom"]
        XCTAssertFalse(settings.exists)
        capture("Medium day shared translucent background")
        let header = app.navigationBars["第1天"]
        let drag = header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: -450)))
        capture("Full height native day background")
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(settings.exists)
        capture("Native trip grouped background")
        app.buttons["journey-back"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        if !settings.isHittable { list.swipeUp() }
        XCTAssertTrue(settings.isHittable)
        capture("Overview grouped background and bottom settings")
        settings.tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        app.buttons["close-settings"].tap()
        let trip = app.buttons["journey-demo-trip"]
        if !trip.isHittable { list.swipeDown() }
        trip.tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(settings.exists)
        app.buttons["itinerary-collapse"].tap()
        app.buttons["itinerary-collapse"].tap()
        capture("Medium pushed trip shared translucent background")
        app.buttons["journey-day-day-1"].tap()
        XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        capture("Medium pushed day shared translucent background")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
