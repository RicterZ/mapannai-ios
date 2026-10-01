import XCTest

final class TripDeletionTests: XCTestCase {
    @MainActor func testNativeDeletionChoiceDefaultsOffAndCancelIsSafe() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        app.buttons["journey-back"].tap(); app.buttons["journey-back"].tap()
        let trip = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-demo")).firstMatch
        let row = trip.exists ? trip : app.buttons["journey-trip-1"]
        if !row.isHittable { app.collectionViews.firstMatch.swipeUp() }
        row.press(forDuration: 1)
        app.buttons["删除旅行"].tap()
        let toggle = app.switches["delete-trip-markers"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
        waitForExpectations(timeout: 3)
        app.buttons["取消"].tap()
        XCTAssertFalse(app.buttons["confirm-delete-trip"].exists)
        XCTAssertTrue(row.exists)
    }
}
