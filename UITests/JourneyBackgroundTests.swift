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
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        app.buttons["close-settings"].tap()
        let trip = app.buttons["journey-demo-trip"]
        if !trip.isHittable { list.swipeDown() }
        trip.tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(settings.exists)
        let tripBar = app.navigationBars["上海 · 秋日散步"]
        let down = tripBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        down.press(forDuration: 0.1, thenDragTo: down.withOffset(CGVector(dx: 0, dy: 550)))
        let panel = app.otherElements["phone-itinerary-panel"]
        XCTAssertTrue(app.otherElements["compact-journey-controls"].waitForExistence(timeout: 5))
        let up = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05))
        up.press(forDuration: 0.1, thenDragTo: up.withOffset(CGVector(dx: 0, dy: -300)))
        capture("Medium pushed trip shared translucent background")
        app.buttons["journey-day-day-1"].tap()
        XCTAssertTrue(app.navigationBars["第1天"].waitForExistence(timeout: 5))
        capture("Medium pushed day shared translucent background")
    }
    @MainActor func testNativeSidebarNavigationAndRouteExpansion() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let marker = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        let toggle = app.buttons.matching(NSPredicate(format: "label == %@", "路线 1, 3个地点")).firstMatch
        XCTAssertTrue(toggle.exists); toggle.tap()
        XCTAssertFalse(marker.exists)
        toggle.tap(); XCTAssertTrue(marker.waitForExistence(timeout: 5))
        app.buttons["journey-back"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        app.buttons["journey-back"].tap()
        let settings = app.buttons["itinerary-settings-bottom"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        capture("Native sidebar overview with settings spacing")
        settings.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        app.buttons["close-settings"].tap()
        app.buttons["journey-demo-trip"].tap()
        app.buttons["journey-day-day-1"].tap()
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        capture("Native sidebar day route disclosure")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
