import XCTest
import UIKit

final class JourneyEditingActionsTests: XCTestCase {
    @MainActor func testRouteHalfSheetFullRowActionsEditTripAndLeftSwipe() throws {
        let isPad = UIDevice.current.userInterfaceIdiom == .pad
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let viewRoute = app.buttons["route-view-0"]
        XCTAssertTrue(viewRoute.waitForExistence(timeout: 10))
        let toggle = app.buttons["route-toggle-0"]
        let firstPlace = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(firstPlace.exists)
        let headerSettled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            toggle.frame.width >= 43.9
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [headerSettled], timeout: 5), .completed)
        XCTAssertLessThanOrEqual(viewRoute.frame.maxX, toggle.frame.minX + 1)
        toggle.tap()
        XCTAssertTrue(firstPlace.waitForNonExistence(timeout: 3))
        viewRoute.tap()
        XCTAssertFalse(firstPlace.exists, "Viewing a collapsed route must not expand it")
        toggle.tap()
        XCTAssertTrue(firstPlace.waitForExistence(timeout: 3))
        if !isPad {
            let bar = app.navigationBars["第1天"]
            let handle = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -450)))
            let panel = app.otherElements["phone-itinerary-panel"]
            XCTAssertGreaterThan(panel.frame.height, 650)
            viewRoute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
            let medium = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                panel.frame.height > 300 && panel.frame.height < 650
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [medium], timeout: 5), .completed)
            handle.press(forDuration: 0.1, thenDragTo: handle.withOffset(CGVector(dx: 0, dy: -450)))
        } else { viewRoute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let place = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(place.waitForExistence(timeout: 5))
        capture("Day before left swipe")
        let cell = app.cells.containing(.button, identifier: "route-0-marker-demo-0").firstMatch
        cell.swipeLeft()
        XCTAssertTrue(app.buttons["删除"].waitForExistence(timeout: 5))
        capture("Route place left swipe delete")
        cell.swipeRight()
        app.buttons["journey-back"].tap()
        let day = app.buttons["journey-day-day-2"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.swipeLeft()
        let delete = app.buttons["删除"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        XCTAssertTrue(app.buttons["confirm-delete-day"].waitForExistence(timeout: 5))
        let choice = app.cells.containing(.staticText, identifier: "delete-day-markers").firstMatch
        XCTAssertFalse(choice.isSelected)
        choice.tap()
        XCTAssertTrue(choice.isSelected)
        app.buttons["取消"].tap()
        let edit = app.buttons["journey-edit-trip"]
        let list = app.collectionViews["itinerary-marker-list"]
        if !edit.isHittable { list.swipeUp() }
        XCTAssertTrue(edit.isHittable)
        XCTAssertGreaterThan(edit.frame.width, 200)
        XCTAssertGreaterThanOrEqual(edit.frame.minY, app.buttons["journey-add-day"].frame.maxY)
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.navigationBars["编辑旅行"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["trip-name-field"].value as? String, "上海 · 秋日散步")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "trip-start-date").firstMatch.exists)
        capture("Trip editing name icon and dates")
        app.buttons["取消"].tap()
        // Read-only demo rejects writes; the alert proves the empty area triggers add-day.
        app.buttons["journey-add-day"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.alerts["无法完成操作"].waitForExistence(timeout: 5))
        app.alerts["无法完成操作"].buttons["知道了"].tap()
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
