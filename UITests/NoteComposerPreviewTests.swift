import XCTest

final class NoteComposerPreviewTests: XCTestCase {
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
