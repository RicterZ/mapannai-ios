import XCTest

final class SettingsAboutTests: XCTestCase {
    @MainActor func testMapEntryHasNoAssistantAndSettingsKeepMapControls() {
        let map = XCUIApplication(); map.launchArguments = ["--demo"]; map.launch()
        XCTAssertTrue(map.buttons["journey-back"].waitForExistence(timeout: 10))
        XCTAssertFalse(map.buttons["open-ai-planner"].exists)
        map.terminate()
        let app = openSettings()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Redesigned settings map and connection"; shot.lifetime = .keepAlways; add(shot)
        XCTAssertFalse(app.switches["hide-ai-chat-icon-toggle"].exists)
        XCTAssertFalse(app.textFields["ai-api-url"].exists)
        let renderer = app.buttons["map-renderer-picker"]
        XCTAssertTrue(renderer.isHittable)
        renderer.tap()
        app.buttons["高德地图"].tap()
        XCTAssertTrue(renderer.label.contains("高德地图"))
        renderer.tap()
        app.buttons["系统地图"].tap()
        XCTAssertTrue(renderer.label.contains("系统地图"))
        XCTAssertTrue(app.buttons["navigation-map-picker"].isHittable)
        XCTAssertTrue(app.switches["planning-toggle"].isHittable)
        app.buttons["close-settings"].tap()
        XCTAssertFalse(app.navigationBars["设置"].exists)
    }

    @MainActor func testInvalidServiceAddressKeepsDraftAndDoesNotCloseSettings() {
        let app = openSettings()
        let field = app.textFields["settings-service-url"]
        if !field.isHittable { app.scrollViews["settings-scroll"].swipeUp() }
        XCTAssertTrue(field.isHittable)
        field.tap(); field.typeText("not-a-url")
        app.buttons["save-settings"].tap()
        let error = app.staticTexts["settings-connection-error"]
        XCTAssertTrue(error.waitForExistence(timeout: 3))
        XCTAssertTrue(error.isHittable)
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.navigationBars["设置"].exists)
        XCTAssertEqual(field.value as? String, "not-a-url")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Settings invalid address preserves draft"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["close-settings"].tap()
    }

    @MainActor private func openSettings() -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--archive-preview"]; app.launch()
        let settings = app.buttons["archive-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        if !settings.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(settings.isHittable); settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor func testRepositoryLinksAndLicenseAppearInSettingsFooter() throws {
        let app = openSettings()
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
