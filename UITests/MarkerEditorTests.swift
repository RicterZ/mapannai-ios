import UIKit
import XCTest

final class MarkerEditorTests: XCTestCase {
    @MainActor func testInlineIconCoverAndFullHeightNotesStayStable() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        if UIDevice.current.userInterfaceIdiom != .pad {
            let handle = app.buttons["itinerary-panel-toggle"]
            XCTAssertTrue(handle.waitForExistence(timeout: 10))
            let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -400)))
        }
        let marker = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(marker.waitForExistence(timeout: 10))
        marker.tap()
        XCTAssertTrue(app.buttons["编辑"].waitForExistence(timeout: 5)); app.buttons["编辑"].tap()
        let name = app.textFields["地点名称"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let icon = app.buttons["marker-icon-picker"]
        let cover = app.buttons["marker-cover-upload"]
        if !cover.isHittable { app.collectionViews.firstMatch.swipeUp() }
        let note = app.textViews["marker-note-editor"]
        XCTAssertTrue(icon.exists); XCTAssertTrue(cover.exists); XCTAssertTrue(note.exists)
        XCTAssertEqual(icon.frame.midY, name.frame.midY, accuracy: 2)
        XCTAssertLessThan(icon.frame.maxX, name.frame.minX)
        XCTAssertLessThan(cover.frame.maxY, note.frame.minY)
        XCTAssertFalse(app.textFields["首图 URL（可选）"].exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'COS'")).firstMatch.exists)
        let initialName = name.frame
        let initialCover = cover.frame
        icon.tap(); app.buttons["美食"].tap()
        XCTAssertTrue(icon.label.contains("美食"))
        XCTAssertEqual(name.frame, initialName)
        XCTAssertEqual(cover.frame, initialCover)
        icon.tap(); app.buttons["自然"].tap()
        XCTAssertTrue(icon.label.contains("自然"))
        XCTAssertEqual(name.frame, initialName)
        XCTAssertEqual(cover.frame, initialCover)
        XCTAssertGreaterThan(note.frame.height, 150)
        XCTAssertLessThanOrEqual(note.frame.maxY, app.windows.firstMatch.frame.maxY - 20)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Inline icon and cover above full height notes"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["取消"].tap()
    }
}
