import XCTest

final class RouteScheduleUITests: XCTestCase {
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
        XCTAssertTrue(leg.waitForExistence(timeout: 5)); leg.press(forDuration: 1)
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
        XCTAssertTrue(leg.waitForExistence(timeout: 5)); leg.press(forDuration: 1)
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
    @MainActor func testDirectedTransportDisconnectsAndRestoresImmediatelyAfterDrop() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--transport-schedule-preview", "--delayed-route-build-preview", "--route-drag-diagnostics"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
        // The redesigned rows include a separate duration line; expose both drop endpoints.
        app.buttons["Sheet Grabber"].swipeUp()
        let a = app.buttons["route-0-marker-demo-0"]
        let b = app.buttons["route-0-marker-demo-1"]
        let c = app.buttons["route-0-marker-demo-2"]
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        b.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["地铁 · 10号线"].exists)
        let initialLayout = expectation(description: "Initial sheet layout settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { initialLayout.fulfill() }
        wait(for: [initialLayout], timeout: 2)
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: app.cells.containing(.button, identifier: "route-0-marker-demo-2").firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.9)), withVelocity: .slow, thenHoldForDuration: 1)
        let updatedOrdinal = expectation(for: NSPredicate(format: "value == %@", "3"), evaluatedWith: b)
        wait(for: [updatedOrdinal], timeout: 2)
        XCTAssertEqual(b.value as? String, "3")
        XCTAssertEqual(c.value as? String, "2")
        XCTAssertFalse(app.staticTexts["地铁 · 10号线"].exists)
        XCTAssertEqual(app.staticTexts["route-drag-diagnostics"].value as? String, "0", "Geometry changes must not update the List during native insertion animation")
        XCTAssertTrue((app.buttons["route-0-schedule-demo-1"].value as? String)?.contains("10:45") == true)
        let disconnected = XCTAttachment(screenshot: app.screenshot())
        disconnected.name = "松手立即断开有向边，游览时间保留"; disconnected.lifetime = .keepAlways; add(disconnected)
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        let restoredOrdinal = expectation(for: NSPredicate(format: "value == %@", "2"), evaluatedWith: b)
        wait(for: [restoredOrdinal], timeout: 2)
        XCTAssertEqual(b.value as? String, "2")
        XCTAssertEqual(c.value as? String, "3")
        XCTAssertTrue(app.staticTexts["地铁 · 10号线"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-demo-1").count, 1)
        XCTAssertEqual(a.value as? String, "1")
        XCTAssertEqual(app.staticTexts["route-drag-diagnostics"].value as? String, "0")
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "拖回原有方向立即恢复交通"; restored.lifetime = .keepAlways; add(restored)
    }

    @MainActor func testHoldRouteDragAtRowMidpoint() {
        for fraction in [0.4, 0.5, 0.6] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--route-drag-diagnostics"]
            app.launch()
            let trip = app.buttons["archive-trip-demo-trip"]
            XCTAssertTrue(trip.waitForExistence(timeout: 10)); trip.tap()
            let day = app.buttons["journey-day-day-1"]
            XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
            let source = app.buttons["route-0-marker-demo-2"]
            let destination = app.cells.containing(.button, identifier: "route-0-marker-demo-1").firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 5))
            app.swipeUp()
            source.press(forDuration: 0.7)
            XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
            let frame = destination.frame
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + frame.width * 0.3, dy: frame.minY + frame.height * fraction))
            source.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
                thenDragTo: end,
                withVelocity: XCUIGestureVelocity(rawValue: 15), thenHoldForDuration: 4)
            XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-demo-2").count, 1)
            XCTAssertEqual(app.staticTexts["route-drag-diagnostics"].value as? String, "0")
            app.terminate()
        }
    }

    @MainActor func testIsolatedPlaceDropsIntoScheduledRouteAfterScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--transport-schedule-preview", "--isolated-transport-drag-preview"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
        app.swipeUp()
        let source = app.buttons["day-marker-demo-3"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        let target = app.buttons["route-0-marker-demo-1"]
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)), withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(app.buttons["route-0-marker-demo-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(source.exists)
        XCTAssertEqual(app.buttons["route-0-marker-demo-3"].value as? String, "2")
        XCTAssertEqual(app.buttons["route-0-marker-demo-1"].value as? String, "3")
    }

}
