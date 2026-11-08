import XCTest

final class TripMarkerNoteUITests: XCTestCase {
    @MainActor private func openPlace(_ markerID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--journey-guide-entry-review", "--trip-note-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let notes = app.buttons["journey-place-notes"].firstMatch
        XCTAssertTrue(notes.waitForExistence(timeout: 10)); notes.tap()
        let place = app.buttons["trip-note-place-" + markerID].firstMatch
        XCTAssertTrue(place.waitForExistence(timeout: 5)); place.tap()
        return app
    }
    @MainActor private func select(_ id: String, in app: XCUIApplication) {
        app.buttons["marker-edit-scope"].tap()
        let option = app.buttons[id]
        XCTAssertTrue(option.waitForExistence(timeout: 3)); option.tap()
    }
    @MainActor func testRetainedNoteUsesOneTopEditorAndCancelPreservesData() {
        let app = openPlace("demo-4")
        XCTAssertTrue(app.staticTexts["保留旅行笔记"].exists)
        let edit = app.buttons["edit-marker-detail"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        let title = app.textFields["trip-note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "已移出日程的活动")
        XCTAssertFalse(app.buttons["复制通用攻略到本次正文"].isEnabled)
        title.tap(); title.typeText("草稿")
        app.buttons["取消"].tap(); app.buttons["放弃修改"].tap()
        XCTAssertTrue(edit.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "已移出日程的活动")
    }
    @MainActor func testOutsideTripDefaultsGeneralAndListsAllMemberships() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--marker-scope-review", "--trip-note-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["marker-membership-next-year"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["trip-note-reading"].exists)
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["trip-note-title"].exists)
        select("edit-scope-next-year", in: app)
        XCTAssertTrue(app.textFields["trip-note-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["trip-note-title"].value as? String, "另一场活动")
    }
    @MainActor func testMembershipSelectionTogglesReadingWithoutNavigation() {
        let app = openPlace("demo-1")
        let next = app.buttons["marker-membership-next-year"]
        next.tap()
        XCTAssertTrue(app.staticTexts["另一场活动"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["edit-marker-detail"].exists)
        next.tap()
        XCTAssertFalse(app.staticTexts["另一场活动"].exists)
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["trip-note-title"].exists)
    }
    @MainActor func testCoverRemovalDraftIsIsolatedAcrossTripSwitches() {
        let app = openPlace("demo-1")
        app.buttons["edit-marker-detail"].tap()
        let remove = app.buttons["trip-note-cover-remove"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5)); remove.tap()
        XCTAssertFalse(remove.exists)
        select("edit-scope-next-year", in: app)
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        select("edit-scope-demo-trip", in: app)
        XCTAssertFalse(remove.exists)
        select("edit-scope-general", in: app)
        XCTAssertFalse(remove.exists)
        select("edit-scope-next-year", in: app)
        XCTAssertTrue(remove.exists)
    }
    @MainActor func testSwitchingGeneralAndTwoTripsKeepsEachDraft() {
        let app = openPlace("demo-1")
        XCTAssertTrue(app.buttons["marker-membership-demo-trip"].exists)
        XCTAssertTrue(app.buttons["marker-membership-next-year"].exists)
        XCTAssertFalse(app.buttons["编辑通用地点"].exists)
        XCTAssertFalse(app.buttons["edit-trip-marker-note"].exists)
        app.buttons["edit-marker-detail"].tap()
        let title = app.textFields["trip-note-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "今年的活动")
        title.tap(); title.typeText("甲")
        select("edit-scope-next-year", in: app)
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "另一场活动")
        title.tap(); title.typeText("乙")
        select("edit-scope-general", in: app)
        let name = app.textFields["marker-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("通用草稿")
        select("edit-scope-demo-trip", in: app)
        XCTAssertEqual(title.value as? String, "今年的活动甲")
        select("edit-scope-next-year", in: app)
        XCTAssertEqual(title.value as? String, "另一场活动乙")
        select("edit-scope-general", in: app)
        XCTAssertEqual(name.value as? String, "武康庭通用草稿")
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "统一编辑 · 分作用域保留草稿"; shot.lifetime = .keepAlways; add(shot)
    }
}
