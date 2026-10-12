import XCTest
import UIKit

final class AIPlannerUITests: XCTestCase {
    @MainActor func testWalletDayAndMapRoundTripPreservesArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--scroll-demo", "--archive-preview"]
        app.launch()
        let card = app.buttons["archive-trip-scroll-trip-12"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let initialY = card.frame.minY
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Wallet journey home"; home.lifetime = .keepAlways; add(home)
        card.tap()
        let close = app.buttons["archive-detail-close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let day = app.buttons["journey-day-scroll-trip-12-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["open-ai-planner"].exists)
        let detail = XCTAttachment(screenshot: app.screenshot())
        detail.name = "Wallet trip days"; detail.lifetime = .keepAlways; add(detail)
        day.tap()
        XCTAssertTrue(app.buttons["archive-day-map"].waitForExistence(timeout: 5))
        app.buttons["archive-day-map"].tap()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 5))
        // Map back traverses day → trip → the full-page trip detail.
        let back = app.buttons["journey-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap(); back.tap()
        XCTAssertTrue(app.buttons["archive-day-map"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
        XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, initialY, accuracy: 2)
        card.press(forDuration: 1)
        XCTAssertTrue(app.buttons["编辑旅行"].waitForExistence(timeout: 3))
    }

    @MainActor func testWalletHeaderScrollsAndClosesFromScrolledPosition() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--scroll-demo", "--archive-preview"]
        app.launch()
        let card = app.buttons["archive-trip-scroll-trip-12"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let originalY = card.frame.minY
        card.tap()
        let first = app.buttons["journey-day-scroll-trip-12-day-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        let hero = app.descendants(matching: .any)["archive-detail-card"].firstMatch
        let y = hero.frame.minY
        XCTAssertLessThan(y, 160)
        XCTAssertLessThan(hero.frame.maxY, first.frame.minY)
        first.swipeUp()
        XCTAssertTrue(!hero.exists || hero.frame.minY < y - 80)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "Trip header scrolls with days"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["archive-detail-close"].tap()
        XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, originalY, accuracy: 2)
        card.tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
    }

    @MainActor func testWalletRepeatedOpenCloseKeepsArchivePosition() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--scroll-demo", "--archive-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
        for id in ["11", "12", "10", "12"] {
            let card = app.buttons["archive-trip-scroll-trip-" + id]
            let oldY = card.frame.minY
            card.tap()
            let close = app.buttons["archive-detail-close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5)); close.tap()
            XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
            XCTAssertEqual(card.frame.minY, oldY, accuracy: 2)
        }
    }

    @MainActor func testLongStreamingReplyStaysAtBottomAfterCompletion() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--ai-chat-preview", "--ai-stream-preview"]
        app.launch()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 10))
        app.buttons["open-ai-planner"].tap()
        let streaming = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "流式末尾：")).firstMatch
        XCTAssertTrue(streaming.waitForExistence(timeout: 10))
        let composer = app.textFields["ai-message-input"]
        XCTAssertLessThanOrEqual(streaming.frame.maxY, composer.frame.minY)
        let completed = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "完成末尾：")).firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["ai-send"].waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(completed.frame.maxY, composer.frame.minY)
        XCTAssertGreaterThan(completed.frame.maxY, composer.frame.minY - 80)
    }

    @MainActor func testChatOpensAtBottomAndComposerDoesNotOverlapMessages() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--ai-chat-preview"]; app.launch()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 10))
        app.buttons["open-ai-planner"].tap()
        let lastReply = app.staticTexts["最新回复：当天行程已整理好。"]
        XCTAssertTrue(lastReply.waitForExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
        let composer = app.otherElements["ai-message-composer"]
        XCTAssertTrue(composer.exists)
        XCTAssertLessThan(lastReply.frame.maxY, composer.frame.minY)
        let input = app.textFields["ai-message-input"]
        XCTAssertTrue(input.isHittable)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "Message bubbles and glass composer"; shot.lifetime = .keepAlways; add(shot)
        let chat = app.scrollViews.firstMatch
        chat.swipeDown()
        XCTAssertTrue(input.isHittable)
        let scrolling = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        scrolling.name = "History scrolling under soft edges"; scrolling.lifetime = .keepAlways; add(scrolling)
        chat.swipeUp()
        input.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(input.isHittable)
        XCTAssertLessThan(input.frame.maxY, app.keyboards.firstMatch.frame.minY)
        let keyboardShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        keyboardShot.name = "Glass composer above keyboard"; keyboardShot.lifetime = .keepAlways; add(keyboardShot)
        app.buttons["ai-close"].tap()
        app.buttons["open-ai-planner"].tap()
        XCTAssertTrue(lastReply.waitForExistence(timeout: 5))
        XCTAssertTrue(lastReply.isHittable)
    }

    @MainActor func testCloseButtonAndConversationMenuPlacement() {
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let entry = app.buttons["open-ai-planner"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.tap()
        let close = app.buttons["ai-close"]
        let topics = app.buttons["ai-conversations"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertTrue(topics.exists)
        XCTAssertLessThan(close.frame.midX, topics.frame.midX)
        close.tap()
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
    }

    @MainActor func testPadEntryToggleAndSettingsGuidance() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad sidebar")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        let entry = app.buttons["open-ai-planner"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        XCTAssertTrue(app.buttons["ai-open-settings"].exists)
        app.buttons["ai-open-settings"].tap()
        let config = app.textFields["ai-api-url"]
        if !config.isHittable { app.collectionViews.firstMatch.swipeUp() }
        XCTAssertTrue(config.waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["ai-model"].exists)
        XCTAssertFalse(app.buttons["ai-configuration-link"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 3))
        entry.tap()
        XCTAssertTrue(app.otherElements["landscape-itinerary-sidebar"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
    }
    @MainActor func testSwipeClosesAssistantAndRestoresJourney() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "Phone system sheet")
        let app = XCUIApplication(); app.launchArguments = ["--demo"]; app.launch()
        XCTAssertTrue(app.buttons["open-ai-planner"].waitForExistence(timeout: 10))
        let entry = app.buttons["open-ai-planner"]
        XCTAssertGreaterThanOrEqual(entry.frame.width, 48)
        XCTAssertGreaterThanOrEqual(entry.frame.height, 48)
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["close-ai-planner"].exists)
        XCTAssertFalse(app.buttons["AI API 配置"].exists)
        XCTAssertTrue(app.otherElements["ai-configuration-prompt"].exists)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "AI centered setup and bottom composer"; shot.lifetime = .keepAlways; add(shot)
        let bar = app.navigationBars.firstMatch
        let drag = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        drag.press(forDuration: 0.1, thenDragTo: drag.withOffset(CGVector(dx: 0, dy: 600)))
        XCTAssertTrue(app.buttons["journey-back"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.textFields["ai-message-input"].exists)
        entry.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["ai-message-input"].waitForExistence(timeout: 5))
    }
}
