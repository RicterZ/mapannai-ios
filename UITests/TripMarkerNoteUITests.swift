import XCTest

final class TripMarkerNoteUITests: XCTestCase {
    @MainActor func testRetainedNoteOpensScopedEditorAndCancelPreservesData() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--journey-guide-entry-review", "--trip-note-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let notes = app.buttons["journey-place-notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10)); notes.tap()
        let retained = app.buttons["trip-note-place-demo-4"].firstMatch
        XCTAssertTrue(retained.waitForExistence(timeout: 5)); retained.tap()
        let edit = app.buttons["edit-trip-marker-note"]
        for _ in 0..<5 {
            if edit.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(edit.isHittable); edit.tap()
        let title = app.textFields["trip-note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "已移出日程的活动")
        XCTAssertTrue(app.staticTexts["愚园路"].exists)
        XCTAssertFalse(app.buttons["复制通用攻略到本次正文"].isEnabled)
        title.tap(); title.typeText("草稿")
        app.buttons["取消"].tap()
        app.buttons["放弃修改"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "已移出日程的活动")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "旅行专属笔记 · 独立标题与真实地点"; shot.lifetime = .keepAlways; add(shot)
    }
}
