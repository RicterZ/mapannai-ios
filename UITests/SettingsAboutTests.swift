import XCTest

final class SettingsAboutTests: XCTestCase {
    @MainActor func testRepositoryLinksAndLicenseAppearInSettingsFooter() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let back = app.buttons["journey-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 10)); back.tap(); back.tap()
        let settings = app.buttons["itinerary-settings-bottom"]
        if !settings.isHittable { app.collectionViews["itinerary-marker-list"].swipeUp() }
        XCTAssertTrue(settings.waitForExistence(timeout: 5)); settings.tap()
        XCTAssertTrue(app.navigationBars["连接设置"].waitForExistence(timeout: 5))
        let ios = app.buttons["about-ios-repository"]
        for _ in 0..<4 where !ios.isHittable { app.swipeUp() }
        XCTAssertTrue(ios.isHittable)
        XCTAssertEqual(ios.label, "RicterZ/mapannai-ios")
        XCTAssertEqual(app.buttons["about-web-repository"].label, "RicterZ/mapannai-plus")
        let license = app.descendants(matching: .any).matching(identifier: "about-license").firstMatch
        XCTAssertTrue(license.exists)
        XCTAssertTrue(license.label.contains("MIT") || (license.value as? String)?.contains("MIT") == true || app.staticTexts["MIT"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Repository and MIT license footer"; shot.lifetime = .keepAlways; add(shot)
    }
}
