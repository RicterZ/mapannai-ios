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
    @MainActor func testCoverSwitchKeepsMembershipControlsInPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--marker-scope-review", "--trip-note-preview", "--cover-order-review", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let first = app.buttons["marker-membership-demo-trip"]
        let next = app.buttons["marker-membership-next-year"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        first.tap()
        let firstFrame = first.frame, nextFrame = next.frame
        let cover = app.descendants(matching: .any)["marker-detail-cover"].firstMatch
        XCTAssertTrue(cover.exists)
        XCTAssertGreaterThanOrEqual(cover.frame.minY, next.frame.maxY)
        next.tap()
        XCTAssertFalse(cover.exists)
        XCTAssertEqual(first.frame.minY, firstFrame.minY, accuracy: 1)
        XCTAssertEqual(next.frame.minY, nextFrame.minY, accuracy: 1)
        next.tap()
        XCTAssertFalse(cover.exists)
        first.tap()
        XCTAssertTrue(cover.exists)
        XCTAssertEqual(first.frame.minY, firstFrame.minY, accuracy: 1)
        XCTAssertEqual(next.frame.minY, nextFrame.minY, accuracy: 1)
        XCTAssertFalse(app.staticTexts["通用笔记（所有旅行共享）"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "封面位于所属行程下方"; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testSharedNotesFollowTripAndStartCollapsed() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--marker-scope-review", "--trip-note-preview", "--shared-note-review", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let tripTitle = app.staticTexts["另一场活动"]
        XCTAssertTrue(tripTitle.waitForExistence(timeout: 8))
        let scroll = app.scrollViews.firstMatch
        scroll.swipeUp()
        let disclosure = app.buttons["marker-general-disclosure"]
        XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
        let sharedBody = app.webViews.staticTexts["跨旅行共享的攻略内容"]
        XCTAssertFalse(sharedBody.exists)
        disclosure.tap()
        XCTAssertTrue(sharedBody.waitForExistence(timeout: 5), app.debugDescription)
        disclosure.tap()
        XCTAssertFalse(sharedBody.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "行程笔记优先、通用笔记折叠"; shot.lifetime = .keepAlways; add(shot)
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
    @MainActor func testOutsideTripSelectsNearestMembershipAndListsAllMemberships() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--marker-scope-review", "--trip-note-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        XCTAssertTrue(app.buttons["marker-membership-next-year"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["另一场活动"].waitForExistence(timeout: 5))
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["trip-note-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["trip-note-title"].value as? String, "另一场活动")
        select("edit-scope-next-year", in: app)
        XCTAssertTrue(app.textFields["trip-note-title"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["trip-note-title"].value as? String, "另一场活动")
    }
    @MainActor func testMembershipReselectionKeepsTripAndSharedNotesStayAvailable() {
        let app = openPlace("demo-1")
        let next = app.buttons["marker-membership-next-year"]
        next.tap()
        XCTAssertTrue(app.staticTexts["另一场活动"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["edit-marker-detail"].exists)
        next.tap()
        XCTAssertTrue(app.staticTexts["另一场活动"].exists)
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["trip-note-title"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["trip-note-title"].value as? String, "另一场活动")
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
