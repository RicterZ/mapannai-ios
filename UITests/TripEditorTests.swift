import XCTest

final class TripEditorTests: XCTestCase {
    @MainActor func testIconNameAndRangeWithoutDescription() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--archive-preview"]; app.launch()
        let create = app.buttons["archive-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        XCTAssertTrue(app.staticTexts["新的旅途"].waitForExistence(timeout: 5))
        let search = app.textFields["trip-destination-search"]
        XCTAssertTrue(search.exists)
        let name = app.textFields["trip-name-field"]
        let icon = app.buttons["trip-icon-picker"]
        let date = app.buttons["trip-date-range"]
        XCTAssertEqual(search.frame.minX, name.frame.minX, accuracy: 1)
        XCTAssertEqual(icon.frame.minX, date.frame.minX, accuracy: 1)
        let inputStart = name.frame.minX
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Aligned trip creation fields"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        search.tap(); search.typeText("京都")
        let result = app.buttons["trip-destination-result-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["trip-destination-remove-0"].exists)
        XCTAssertTrue(name.exists); XCTAssertTrue(icon.exists)
        XCTAssertEqual(icon.frame.midY, name.frame.midY, accuracy: 2)
        XCTAssertLessThan(icon.frame.maxX, name.frame.minX)
        XCTAssertFalse(app.textFields["简介"].exists)
        XCTAssertFalse(app.buttons["trip-create-submit"].isEnabled)
        icon.tap(); app.buttons["trip-icon-option-🏍️"].tap()
        XCTAssertTrue(icon.label.contains("🏍️"))
        name.tap(); name.typeText("Weekend ride")
        XCTAssertTrue(app.buttons["trip-create-submit"].isEnabled)
        XCTAssertTrue(app.buttons["trip-date-range"].exists)
        date.tap()
        XCTAssertEqual(name.frame.minX, inputStart, accuracy: 1)
        app.buttons["trip-create-cancel"].tap()
    }
    @MainActor func testLargerNotesKeepTypingAndFormatting() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let handle = app.buttons["itinerary-panel-toggle"]
        let header = handle.exists ? handle : app.navigationBars["第1天"]
        XCTAssertTrue(header.waitForExistence(timeout: 10))
        let start = header.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.15))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
        let marker = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5)); app.buttons["编辑"].tap()
        let note = app.textViews["marker-note-editor"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        if !note.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue((note.value as? String)?.contains("示例地点笔记") == true)
        note.tap(); note.typeText(" More notes")
        XCTAssertTrue((note.value as? String)?.contains("More notes") == true)
        app.buttons["粗体"].tap()
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Larger existing and typed marker notes"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["取消"].tap()
    }

}
