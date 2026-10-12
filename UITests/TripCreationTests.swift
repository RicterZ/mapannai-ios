import XCTest

final class TripCreationTests: XCTestCase {
    @MainActor func testFullPageCreationRangeKeyboardAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let archive = app.buttons["archive-create"]
        XCTAssertTrue(archive.waitForExistence(timeout: 10)); archive.tap()
        XCTAssertTrue(app.staticTexts["新的旅途"].waitForExistence(timeout: 5))
        let cancel = app.buttons["trip-create-cancel"]
        let navigationY = cancel.frame.minY
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        let search = app.textFields["trip-destination-search"]
        XCTAssertTrue(search.exists)
        capture(app, "New trip destination search")
        search.tap(); search.typeText("京都")
        let result = app.buttons["trip-destination-result-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        capture(app, "New trip destination results")
        result.tap()
        XCTAssertTrue(app.buttons["trip-destination-remove-0"].exists)
        search.tap(); search.typeText("东京")
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["trip-destination-remove-1"].exists)
        capture(app, "New trip multiple destinations")
        search.tap(); search.typeText("京都")
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(result.isEnabled)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2))
        app.buttons["trip-destination-remove-1"].tap()
        let name = app.textFields["trip-name-field"]
        let icon = app.buttons["trip-icon-picker"]
        let submit = app.buttons["trip-create-submit"]
        XCTAssertFalse(submit.isEnabled)
        XCTAssertEqual(icon.frame.midY, name.frame.midY, accuracy: 2)
        capture(app, "New trip destination selected")
        app.buttons["trip-destination-remove-0"].tap()
        search.typeText("不存在的省市")
        XCTAssertTrue(app.staticTexts["trip-destination-error"].waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled)
        search.tap()
        // Replace the query using the field's current value, without relying on a localized editing menu.
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: (search.value as? String)?.count ?? 0) + "京都")
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        icon.tap()
        XCTAssertTrue(app.scrollViews["trip-icon-panel"].waitForExistence(timeout: 5))
        let row = ["✈️", "🚞", "🚢", "🚗", "🏍️"].map { app.buttons["trip-icon-option-" + $0] }
        for button in row { XCTAssertTrue(button.isHittable); XCTAssertEqual(button.frame.midY, row[0].frame.midY, accuracy: 2) }
        capture(app, "New trip icon panel")
        let lastIcon = app.buttons["trip-icon-option-🍕"]
        for _ in 0..<3 where !lastIcon.isHittable { app.scrollViews["trip-icon-panel"].swipeUp() }
        XCTAssertTrue(lastIcon.isHittable)
        lastIcon.tap()
        XCTAssertTrue(icon.label.contains("🍕"))
        icon.tap()
        app.buttons["trip-icon-option-🏍️"].tap()
        XCTAssertTrue(icon.label.contains("🏍️"))
        name.tap(); name.typeText("京都秋日漫游")
        XCTAssertTrue(submit.isEnabled)
        XCTAssertEqual(cancel.frame.minY, navigationY, accuracy: 2)
        XCTAssertTrue(cancel.isHittable)
        XCTAssertLessThanOrEqual(submit.frame.maxY, app.keyboards.firstMatch.frame.minY)
        capture(app, "New trip keyboard")
        // Opening the range dismisses the keyboard and keeps the name.
        app.buttons["trip-date-range"].tap()
        XCTAssertTrue(app.otherElements["trip-range-calendar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertEqual(cancel.frame.minY, navigationY, accuracy: 2)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let month = calendar.dateInterval(of: .month, for: .now)!.start
        let first = calendar.date(byAdding: .day, value: 18, to: month)!
        let last = calendar.date(byAdding: .day, value: 21, to: month)!
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd"; formatter.calendar = calendar; formatter.timeZone = .current
        app.buttons["trip-range-day-" + formatter.string(from: first)].tap()
        app.buttons["trip-range-day-" + formatter.string(from: last)].tap()
        XCTAssertTrue(app.staticTexts["trip-date-summary"].label.contains("共 4 天"))
        app.buttons["trip-month-next"].tap()
        app.buttons["trip-month-previous"].tap()
        capture(app, "New trip date range")
        let done = app.buttons["trip-range-done"]
        if done.frame.maxY >= submit.frame.minY { app.scrollViews.firstMatch.swipeUp() }
        done.tap()
        app.scrollViews.firstMatch.swipeDown()
        XCTAssertEqual(name.value as? String, "京都秋日漫游")
        app.buttons["trip-date-range"].tap()
        XCTAssertTrue(app.buttons["trip-range-day-" + formatter.string(from: first)].value as? String == "日期范围端点")
        app.buttons["trip-month-next"].tap()
        app.buttons["trip-month-previous"].tap()
        XCTAssertTrue(app.staticTexts["trip-date-summary"].label.contains("共 4 天"))
        app.buttons["trip-create-cancel"].tap()
        XCTAssertTrue(archive.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["京都秋日漫游"].exists)
    }
    @MainActor private func capture(_ app: XCUIApplication, _ title: String) {
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot()); image.name = title; image.lifetime = .keepAlways; add(image)
    }
}
