import XCTest

final class NoteComposerPreviewTests: XCTestCase {
    @MainActor func testPlaceEditorUsesRealComposerAndRetainsNoteDraft() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo"]
        app.launch()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5))
        app.buttons["编辑"].tap()
        let note = app.buttons["marker-note-editor"]
        if !note.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        let editor = app.textViews["note-composer-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["武康路散步记录"].exists)
        editor.typeText("新笔记回填测试")
        app.buttons["保存笔记"].tap()
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        note.tap()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue((editor.value as? String ?? "").contains("新笔记回填测试"))
    }

    @MainActor func testNativeComposerKeepsFormattingAndPhotosAboveKeyboard() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--note-composer-preview"]
        app.launch()
        let editor = app.textViews["note-composer-text"]
        XCTAssertTrue(editor.waitForExistence(timeout: 10))
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "Opening the composer automatically focuses the note")
        editor.typeText(" ")
        let bullet = app.buttons["项目列表"]
        XCTAssertTrue(bullet.isHittable)
        XCTAssertLessThanOrEqual(bullet.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        XCTAssertTrue(app.buttons["添加图片，可多选"].isHittable)
        XCTAssertTrue(app.buttons["保存笔记"].isHittable)
        Thread.sleep(forTimeInterval: 0.8)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Native note composer with keyboard — local sample images"
        shot.lifetime = .keepAlways
        add(shot)
    }
}
