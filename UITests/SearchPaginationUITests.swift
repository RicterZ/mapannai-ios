import XCTest
import UIKit
final class SearchPaginationUITests: XCTestCase {
    @MainActor func testScrollLoadsBeyondTwentyAndChangingQueryRestartsResults() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--paged-search-demo"]
        if UIDevice.current.userInterfaceIdiom == .pad { XCUIDevice.shared.orientation = .landscapeLeft }
        defer { XCUIDevice.shared.orientation = .portrait }
        app.launch()
        let list = app.collectionViews["itinerary-marker-list"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        if UIDevice.current.userInterfaceIdiom == .phone {
            let bar = app.navigationBars["第1天"]
            let start = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -450)))
        }
        let addButton = app.buttons["day-search-add-place"]
        for _ in 0..<5 where !addButton.isHittable { list.swipeUp() }
        XCTAssertTrue(addButton.isHittable); addButton.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("咖啡\n")
        let last = app.buttons["add-place-result-paged-44"]
        let results = app.collectionViews["add-place-results"]
        for _ in 0..<16 where !last.isHittable { results.swipeUp() }
        XCTAssertTrue(last.isHittable)
        XCTAssertTrue(last.label.contains("45"))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Search page three beyond twenty"; screenshot.lifetime = .keepAlways; add(screenshot)
        for _ in 0..<16 where !search.isHittable { results.swipeDown() }
        XCTAssertTrue(search.isHittable)
        search.tap()
        // UISearchBar's clear button cancels all existing pages before a new query.
        if app.buttons["Clear text"].exists { app.buttons["Clear text"].tap() }
        else { search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 2)) }
        search.typeText("公园\n")
        let first = app.buttons["add-place-result-paged-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("公园"))
        XCTAssertFalse(app.staticTexts["咖啡 45"].exists)
    }
}
