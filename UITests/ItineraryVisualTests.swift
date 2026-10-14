import XCTest

final class ItineraryVisualTests: XCTestCase {
    @MainActor func testBrowseAndFullScreenEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--inline-address-preview", "--day-detail-style-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["route-0-marker-demo-0"].waitForExistence(timeout: 10))
        capture("01-browse")
        let edit = app.buttons["day-edit-places"]
        for _ in 0..<5 where !edit.isHittable { app.swipeUp() }
        XCTAssertTrue(edit.isHittable); edit.tap()
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["route-actions-0"].exists)
        XCTAssertTrue(app.staticTexts["route-0-schedule-note-demo-0"].exists)
        capture("02-fullscreen-edit")
        let schedule = app.buttons.matching(NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "route-0-schedule-demo-0", "09:30")).firstMatch
        XCTAssertTrue(schedule.waitForExistence(timeout: 5)); schedule.tap()
        XCTAssertTrue(app.textViews.firstMatch.waitForExistence(timeout: 5) || app.navigationBars["游览安排"].exists)
        capture("03-schedule")
        app.scrollViews["schedule-editor-scroll"].swipeRight()
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        app.otherElements["route-0-transport-0"].firstMatch.tap()
        XCTAssertTrue(app.textFields["schedule-service"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule-mode-walking"].exists)
        capture("04-transport")
        app.scrollViews["schedule-editor-scroll"].swipeRight()
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
