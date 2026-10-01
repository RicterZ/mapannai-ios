import XCTest
import UIKit

final class SearchMapTests: XCTestCase {
    @MainActor func testSearchPinsHalfSheetRepeatTapAndRetainedQuery() {
        guard UIDevice.current.userInterfaceIdiom != .pad else { return }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        let list = app.collectionViews["itinerary-marker-list"]
        for _ in 0..<4 where !add.isHittable { list.swipeUp() }
        add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        screenshot("Add place search container before typing")
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        let name = app.textFields["地点名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "静安寺")
        XCTAssertGreaterThan(name.frame.minY, app.windows.firstMatch.frame.height * 0.35)
        let pin = app.buttons["map-search-result-demo-3"]
        XCTAssertTrue(pin.isHittable)
        screenshot("Search results and half-height editor")
        pin.tap()
        let expanded = NSPredicate { _, _ in name.frame.minY < app.windows.firstMatch.frame.height * 0.35 }
        expectation(for: expanded, evaluatedWith: name); waitForExpectations(timeout: 5)
        XCTAssertEqual(name.value as? String, "静安寺")
        let note = app.textViews["marker-note-editor"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(note.frame.maxY, app.windows.firstMatch.frame.maxY)
        screenshot("Repeated result tap expands editor")
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
        XCTAssertTrue(pin.exists)
        search.buttons.firstMatch.tap()
        XCTAssertFalse(pin.exists)
    }
    @MainActor func testDayAddSearchCollapsesJourneyAndMapPinOpensEditor() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 10))
        let list = app.collectionViews["itinerary-marker-list"]
        for _ in 0..<4 where !add.isHittable { list.swipeUp() }
        XCTAssertTrue(add.isHittable); add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(search.frame.minY, app.windows.firstMatch.frame.height * 0.4)
        screenshot("Add place search container before typing")
        search.tap(); search.typeText("静安\n")
        let pin = app.buttons["map-search-result-demo-3"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5)); XCTAssertTrue(pin.isHittable)
        pin.tap()
        XCTAssertTrue(app.textFields["地点名称"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["地点名称"].value as? String, "静安寺")
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "静安")
        app.buttons["add-place-result-demo-3"].tap()
        XCTAssertTrue(app.textFields["地点名称"].waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["close-place-picker"].tap()
        XCTAssertFalse(pin.exists)
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

final class IPadMarkerDialogTests: XCTestCase {
    @MainActor func testSearchPlaceOpensCenteredFixedDialogAndCancelPreservesResults() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "Centered dialog requires iPad")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]
        XCUIDevice.shared.orientation = .landscapeLeft; app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("武康\n")
        let result = app.buttons["search-result-demo-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let bar = app.navigationBars["添加地点"]
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        let name = app.textFields["地点名称"]
        XCTAssertEqual(name.value as? String, "武康大楼")
        let window = app.windows.firstMatch
        XCTAssertEqual(bar.frame.midX, window.frame.midX, accuracy: 3)
        XCTAssertGreaterThan(bar.frame.minX, window.frame.width * 0.15)
        XCTAssertLessThan(bar.frame.maxX, window.frame.width * 0.85)
        XCTAssertGreaterThan(bar.frame.minY, 40)
        XCTAssertLessThan(bar.frame.minY, window.frame.height * 0.3)
        let initial = bar.frame
        let note = app.textViews["marker-note-editor"]
        XCTAssertTrue(note.exists)
        XCTAssertGreaterThan(note.frame.height, 180)
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 180)))
        XCTAssertTrue(bar.exists)
        XCTAssertEqual(bar.frame, initial)
        let image = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        image.name = "iPad centered fixed marker editor"; image.lifetime = .keepAlways; add(image)
        app.buttons["取消"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "武康")
        XCTAssertTrue(app.buttons["map-search-result-demo-0"].exists)
    }

}
