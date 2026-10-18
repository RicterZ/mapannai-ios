import XCTest

final class JourneyGuideUITests: XCTestCase {
    @MainActor func testGuideFooterHasOnlyThreeMatchingActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--journey-guide-entry-review", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let guide = app.buttons["journey-guide"].firstMatch
        for _ in 0..<12 {
            if guide.exists && guide.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(guide.isHittable)
        XCTAssertFalse(app.buttons["trip-add-place"].exists)
        let edit = app.buttons["journey-edit-trip"].firstMatch
        let addDay = app.buttons["journey-add-day"].firstMatch
        XCTAssertTrue(edit.exists); XCTAssertTrue(addDay.exists)
        let firstDay = app.buttons["journey-day-day-1"].firstMatch
        XCTAssertTrue(firstDay.exists)
        XCTAssertLessThanOrEqual(guide.frame.maxY, firstDay.frame.minY)
        XCTAssertEqual(guide.frame.midY, edit.frame.midY, accuracy: 2)
        XCTAssertEqual(guide.frame.midY, addDay.frame.midY, accuracy: 2)
        let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.lifetime = .keepAlways; attachment.name = "导览独立按钮行"; add(attachment)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/mapannai-guide-entry-verified.png"))
    }
    @MainActor func testGuideUsesInteractiveMapInsteadOfImage() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--journey-guide-review", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 10))
        app.buttons["guide-scope-menu"].tap()
        let day = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第2天")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 3)); day.tap()
        XCTAssertTrue(app.buttons["guide-scope-menu"].label.contains("第2天"))
        XCTAssertTrue(app.maps.firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "全程导览 · 原生地图缩放拖动"
        attachment.lifetime = .keepAlways
        add(attachment)
        try? app.screenshot().pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/mapannai-guide-day-verified.png"))
    }
}
