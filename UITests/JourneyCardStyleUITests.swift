import XCTest

final class JourneyCardStyleUITests: XCTestCase {
    @MainActor func testDayCardsAndPhotoArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--journey-card-style-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Local fixture photos must be decoded before exercising the snapshot transition.
        sleep(3)
        attach(app, "Native journey home")
        let initialY = card.frame.minY
        card.tap()
        let first = app.buttons["journey-day-day-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("09:30 首站"))
        XCTAssertTrue(first.label.contains("地铁"))
        sleep(1)
        attach(app, "Native day cards with photos")
        first.swipeUp()
        attach(app, "Native day cards no theme and empty day")
        XCTAssertTrue(app.buttons["journey-edit-trip"].exists)
        app.buttons["journey-edit-trip"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        first.swipeDown()
        first.tap()
        sleep(1)
        app.swipeUp()
        attach(app, "Native day action capsules")
        XCTAssertTrue(app.buttons["day-search-add-place"].exists)
        app.buttons["新建路线"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["archive-detail-close"].tap()
        XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, initialY, accuracy: 2)
        app.swipeUp()
        let settings = app.buttons["archive-settings"]
        XCTAssertTrue(settings.isHittable)
        attach(app, "Native archive settings capsule")
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    }
    @MainActor func testDayDetailVisualsAndEditors() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--route-distance-preview", "--day-detail-style-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let schedule = app.buttons["route-0-schedule-demo-0"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["map-day-trip-title"].exists)
        attach(app, "Day detail scheduled")
        XCTAssertTrue(app.staticTexts["沿街散步，看看老建筑。"].exists)
        schedule.tap()
        XCTAssertTrue(app.textFields["schedule-duration"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schedule-duration"].value as? String, "60")
        app.buttons["取消"].tap()
        app.buttons["route-0-transport-0"].tap()
        XCTAssertTrue(app.textFields["schedule-service"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schedule-service"].value as? String, "10号线")
        app.buttons["取消"].tap()
        app.buttons["route-toggle-0"].tap()
        XCTAssertFalse(schedule.exists)
        attach(app, "Day detail collapsed")
        app.buttons["route-toggle-0"].tap()
        XCTAssertTrue(schedule.waitForExistence(timeout: 3))
    }
    @MainActor func testDayDetailLegacyAndLargeType() {
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--archive-preview", "--route-distance-preview"]
            if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            let card = app.buttons["archive-trip-demo-trip"]
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
            let day = app.buttons["journey-day-day-1"]
            XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
            XCTAssertTrue(app.buttons["route-0-marker-demo-0"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["route-0-transport-0"].exists)
            attach(app, large ? "Day detail accessibility type" : "Day detail legacy distance")
            app.terminate()
        }
    }
    @MainActor func testDayDetailLongNameAndUntitledHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--day-detail-style-preview", "--day-detail-long-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        XCTAssertTrue(app.buttons["route-0-schedule-demo-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-marker-demo-3"].exists)
        let note = app.staticTexts["先到沿街入口集合，参观前核对预约时间；雨天从侧门进入，沿着连廊前往展厅。"]
        XCTAssertGreaterThan(note.frame.height, 20)
        attach(app, "Day detail long name without theme")
        app.buttons["route-0-marker-demo-0"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(note.exists)
        XCTAssertFalse(app.buttons["route-0-schedule-demo-0"].exists)
        XCTAssertFalse(app.buttons["route-0-transport-0"].exists)
        XCTAssertLessThanOrEqual(app.buttons["day-selection-move"].frame.height, 48)
        XCTAssertLessThanOrEqual(app.buttons["route-0-marker-demo-0"].frame.height, 60)
        attach(app, "Day detail compact selection layout")
        app.buttons["day-edit-done"].tap()
        XCTAssertTrue(app.buttons["route-0-schedule-demo-0"].exists)
    }
    @MainActor func testDeletedDayMemberDoesNotShowEmptyUnscheduledGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--day-stale-member-preview"]
        app.launch()
        app.buttons["archive-trip-demo-trip"].tap()
        XCTAssertFalse(app.buttons["archive-detail-map"].exists)
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        day.tap()
        XCTAssertTrue(app.staticTexts["map-day-trip-title"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["route-0-marker-demo-2"].exists)
        XCTAssertFalse(app.staticTexts["未安排"].exists)
        XCTAssertFalse(app.buttons["day-marker-deleted-marker"].exists)
        attach(app, "Deleted member excluded; day has three actual places")
    }
    @MainActor func testUnscheduledPlacesStyle() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--trip-places-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        app.swipeUp()
        let place = app.buttons["trip-unscheduled-preview-cafe"]
        XCTAssertTrue(place.isHittable)
        XCTAssertTrue(app.buttons["trip-add-place"].exists)
        attach(app, "Unscheduled places and compact actions")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
