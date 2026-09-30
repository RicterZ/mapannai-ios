import XCTest

final class TripEditorTests: XCTestCase {
    @MainActor func testInlineIconNameAndDatesWithoutDescription() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let exit = app.buttons["exit-journey"]
        XCTAssertTrue(exit.waitForExistence(timeout: 10)); exit.tap()
        let create = app.buttons["create-journey"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.navigationBars["创建旅行"].waitForExistence(timeout: 5))
        let name = app.textFields["trip-name-field"]
        let icon = app.buttons["trip-icon-picker"]
        XCTAssertTrue(name.exists); XCTAssertTrue(icon.exists)
        XCTAssertEqual(icon.frame.midY, name.frame.midY, accuracy: 2)
        XCTAssertLessThan(icon.frame.maxX, name.frame.minX)
        XCTAssertFalse(app.textFields["简介"].exists)
        XCTAssertFalse(app.textFields["旅行图标"].exists)
        XCTAssertFalse(app.buttons["保存"].isEnabled)
        icon.tap(); app.buttons["trip-icon-option-🏍️"].tap()
        XCTAssertTrue(icon.label.contains("🏍️"))
        name.tap(); name.typeText("Weekend ride")
        XCTAssertTrue(app.buttons["保存"].isEnabled)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Inline trip editor"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["取消"].tap()
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
