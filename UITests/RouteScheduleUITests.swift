import XCTest

final class RouteScheduleUITests: XCTestCase {
    @MainActor func testVisitSaveScrollsWithContentAndNoteShowsFiveLines() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(1)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1)); day.tap()
        let visit = app.buttons["route-0-schedule-demo-0"]
        XCTAssertTrue(visit.waitForExistence(timeout: 5)); visit.tap()
        let scroll = app.scrollViews["schedule-editor-scroll"]
        XCTAssertTrue(scroll.waitForExistence(timeout: 5))
        let save = scroll.buttons["schedule-save"]
        XCTAssertTrue(save.exists, "Visit save must belong to the scrolling content")
        XCTAssertGreaterThan(app.textFields["schedule-note"].frame.height, 120)
        for _ in 0..<3 where !save.isHittable { scroll.swipeUp() }
        XCTAssertTrue(save.isHittable)
        let originalY = save.frame.minY
        scroll.swipeDown()
        XCTAssertGreaterThan(save.frame.minY, originalY + 20, "Save must not float above the scrolling page")
    }

    @MainActor func testTransportEditorDesignAndCancelPreservesSchedule() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--route-distance-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 10)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let leg = app.otherElements["route-0-transport-0"].firstMatch
        XCTAssertTrue(leg.waitForExistence(timeout: 5))
        let edit = leg.buttons["transport-edit"]
        XCTAssertTrue(edit.isHittable)
        XCTAssertGreaterThan(edit.frame.midX, leg.frame.midX)
        XCTAssertLessThanOrEqual(edit.frame.maxX, leg.frame.maxX)
        XCTAssertGreaterThanOrEqual(edit.frame.minY, leg.frame.minY)
        XCTAssertLessThanOrEqual(edit.frame.maxY, leg.frame.maxY)
        edit.tap()
        let service = app.textFields["schedule-service"]
        XCTAssertTrue(service.waitForExistence(timeout: 5))
        XCTAssertEqual(service.value as? String, "10号线")
        XCTAssertEqual(app.textFields["schedule-duration"].value as? String, "15")
        XCTAssertTrue(app.buttons["schedule-mode-subway"].isSelected)
        XCTAssertTrue(app.buttons["schedule-save"].exists)
        capture(app, "交通安排 · 交通方式与车次")
        app.buttons["schedule-mode-train"].tap()
        XCTAssertTrue(app.buttons["schedule-mode-train"].isSelected)
        XCTAssertFalse(app.buttons["schedule-mode-subway"].isSelected)
        let scroll = app.scrollViews["schedule-editor-scroll"]
        if !app.buttons["schedule-clear"].isHittable { scroll.swipeUp() }
        XCTAssertTrue(app.textFields["schedule-duration"].isHittable)
        XCTAssertTrue(app.buttons["schedule-clear"].isHittable)
        capture(app, "交通安排 · 时间备注与操作")
        app.buttons["schedule-cancel"].tap()
        XCTAssertTrue(leg.waitForExistence(timeout: 5)); edit.tap()
        XCTAssertTrue(service.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["schedule-mode-subway"].isSelected, "取消不能保存交通方式修改")
        XCTAssertEqual(service.value as? String, "10号线")
        app.buttons["schedule-cancel"].tap()
        let visit = app.buttons["route-0-schedule-demo-1"]
        XCTAssertTrue(visit.waitForExistence(timeout: 5)); visit.tap()
        XCTAssertTrue(app.textFields["schedule-duration"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["schedule-mode-walking"].exists)
        XCTAssertTrue(app.navigationBars["游览安排"].exists)
        capture(app, "游览安排 · 共用设计语言")
        app.buttons["schedule-cancel"].tap()
    }
    @MainActor private func capture(_ app: XCUIApplication, _ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
