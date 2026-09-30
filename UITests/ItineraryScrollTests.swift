import XCTest
import UIKit

final class ItineraryScrollTests: XCTestCase {
    @MainActor func testOverviewDaysAndDateSwitchesStartAtTop() throws {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--scroll-demo"]
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let list = app.collectionViews["itinerary-marker-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        list.swipeUp()
        let trip = try XCTUnwrap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "journey-scroll-trip-"))
            .allElementsBoundByIndex.last { $0.isHittable && $0.frame.minY >= list.frame.minY && $0.frame.maxY <= list.frame.maxY })
        let tripID = String(trip.identifier.dropFirst("journey-".count))
        trip.tap()
        let firstDay = app.buttons["journey-day-\(tripID)-day-1"]
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5))
        assertAtTop(firstDay, list: list)
        list.swipeUp()
        let laterDay = app.buttons["journey-day-\(tripID)-day-7"]
        for _ in 0..<4 where !laterDay.isHittable { list.swipeUp() }
        XCTAssertTrue(laterDay.isHittable)
        if laterDay.frame.minY < list.frame.minY { list.swipeDown() }
        laterDay.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).tap()
        let route = app.buttons["route-toggle-0"]
        XCTAssertTrue(route.waitForExistence(timeout: 5)); assertAtTop(route, list: list)
        list.swipeUp(); list.swipeUp()
        if !app.buttons["date-selector"].exists { app.buttons["itinerary-collapse"].tap() }
        app.buttons["date-selector"].tap()
        let next = app.buttons["date-option-\(tripID)-day-2"]
        XCTAssertTrue(next.waitForExistence(timeout: 5)); next.tap()
        if UIDevice.current.userInterfaceIdiom == .phone { app.buttons["itinerary-collapse"].tap() }
        XCTAssertTrue(route.waitForExistence(timeout: 5)); assertAtTop(route, list: list)
        list.swipeUp()
        if !app.buttons["trip-breadcrumb"].exists { app.buttons["itinerary-collapse"].tap() }
        app.buttons["trip-breadcrumb"].tap()
        if UIDevice.current.userInterfaceIdiom == .phone { app.buttons["itinerary-collapse"].tap() }
        XCTAssertTrue(firstDay.waitForExistence(timeout: 5)); assertAtTop(firstDay, list: list)
        list.swipeUp()
        if !app.buttons["exit-journey"].exists { app.buttons["itinerary-collapse"].tap() }
        app.buttons["exit-journey"].tap()
        let create = app.buttons["create-journey"]
        if UIDevice.current.userInterfaceIdiom == .phone { app.buttons["itinerary-collapse"].tap() }
        XCTAssertTrue(create.waitForExistence(timeout: 5)); assertAtTop(create, list: list)
    }
    private func assertAtTop(_ element: XCUIElement, list: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.isHittable, file: file, line: line)
        let search = XCUIApplication().searchFields["map-place-search"]
        XCTAssertTrue(search.isHittable, file: file, line: line)
        let navigationBar = XCUIApplication().navigationBars.firstMatch
        let contentTop = navigationBar.exists ? max(list.frame.minY, navigationBar.frame.maxY) : list.frame.minY
        XCTAssertGreaterThanOrEqual(search.frame.minY, contentTop, file: file, line: line)
        XCTAssertLessThan(search.frame.minY - contentTop, 70, file: file, line: line)
    }
}
