import XCTest

final class TripDeletionTests: XCTestCase {
    @MainActor func testNativeDeletionChoiceDefaultsOffAndCancelIsSafe() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        for _ in 0..<2 {
            let back = app.buttons.matching(identifier: "journey-back").allElementsBoundByIndex.first { $0.isHittable }
            XCTAssertNotNil(back)
            back?.tap()
        }
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-demo")).firstMatch
        let row = trip.exists ? trip : app.buttons["journey-trip-1"]
        if !row.isHittable { app.collectionViews.firstMatch.swipeUp() }
        row.press(forDuration: 1)
        app.buttons["删除旅行"].tap()
        let option = app.staticTexts["delete-trip-markers"]
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        let rowChoice = app.cells.containing(.staticText, identifier: "delete-trip-markers").firstMatch
        XCTAssertFalse(rowChoice.isSelected)
        rowChoice.tap()
        expectation(for: NSPredicate(format: "selected == true"), evaluatedWith: rowChoice)
        waitForExpectations(timeout: 3)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Native trip deletion checkmark"
        shot.lifetime = .keepAlways
        add(shot)
        app.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["confirm-delete-trip"].exists)
        XCTAssertTrue(row.exists)
    }
}
