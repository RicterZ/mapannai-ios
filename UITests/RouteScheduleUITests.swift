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
}
