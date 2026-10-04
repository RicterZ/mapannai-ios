import XCTest

final class RouteScheduleUITests: XCTestCase {
    @MainActor func testTransportSummaryAndNativeEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--transport-schedule-preview", "--route-distance-preview"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
        let leg = app.buttons["route-0-transport-0"]
        XCTAssertTrue(leg.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["10号线"].exists)
        let list = XCTAttachment(screenshot: app.screenshot()); list.name = "交通安排列表"; list.lifetime = .keepAlways; add(list)
        leg.tap()
        let service = app.textFields["schedule-service"]
        XCTAssertTrue(service.waitForExistence(timeout: 5))
        XCTAssertEqual(service.value as? String, "10号线")
        XCTAssertEqual(app.textFields["schedule-duration"].value as? String, "15")
        XCTAssertTrue(app.buttons["schedule-save"].exists)
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "交通安排原生表单"; form.lifetime = .keepAlways; add(form)
        app.buttons["取消"].tap()
        XCTAssertTrue(leg.waitForExistence(timeout: 5))
        app.buttons["route-0-transport-1"].tap()
        XCTAssertTrue(service.waitForExistence(timeout: 5))
        XCTAssertEqual(service.value as? String, "未设置")
        XCTAssertFalse(app.buttons["schedule-clear"].exists)
    }
    @MainActor func testDirectedTransportDisconnectsAndRestoresImmediatelyAfterDrop() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--transport-schedule-preview", "--delayed-route-build-preview"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 10)); day.tap()
        let a = app.buttons["route-0-marker-demo-0"]
        let b = app.buttons["route-0-marker-demo-1"]
        let c = app.buttons["route-0-marker-demo-2"]
        XCTAssertTrue(b.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["10号线"].exists)
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.8)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertEqual(b.value as? String, "3")
        XCTAssertEqual(c.value as? String, "2")
        XCTAssertFalse(app.staticTexts["10号线"].exists)
        XCTAssertTrue((app.buttons["route-0-schedule-demo-1"].value as? String)?.contains("10:45") == true)
        let disconnected = XCTAttachment(screenshot: app.screenshot())
        disconnected.name = "松手立即断开有向边，游览时间保留"; disconnected.lifetime = .keepAlways; add(disconnected)
        b.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: c.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.1)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertEqual(b.value as? String, "2")
        XCTAssertEqual(c.value as? String, "3")
        XCTAssertTrue(app.staticTexts["10号线"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "route-0-marker-demo-1").count, 1)
        XCTAssertEqual(a.value as? String, "1")
        let restored = XCTAttachment(screenshot: app.screenshot())
        restored.name = "拖回原有方向立即恢复交通"; restored.lifetime = .keepAlways; add(restored)
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
        let target = app.buttons["route-0-marker-demo-1"]
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2,
            thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.2)), withVelocity: .slow, thenHoldForDuration: 1)
        XCTAssertTrue(app.buttons["route-0-marker-demo-3"].waitForExistence(timeout: 5))
        XCTAssertFalse(source.exists)
        XCTAssertEqual(app.buttons["route-0-marker-demo-3"].value as? String, "2")
        XCTAssertEqual(app.buttons["route-0-marker-demo-1"].value as? String, "3")
    }

}
