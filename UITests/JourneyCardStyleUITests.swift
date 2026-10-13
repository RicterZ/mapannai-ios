import XCTest

final class JourneyCardStyleUITests: XCTestCase {
    @MainActor func testSavedPlaceCardsAboveChatAndOpenDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--saved-places-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let heading = app.staticTexts["archive-saved-places-heading"]
        for _ in 0..<5 where !heading.isHittable { app.swipeUp() }
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "收藏地点")
        XCTAssertFalse(app.staticTexts["未加入行程"].exists)
        let photoCard = app.buttons["independent-marker-demo-3"]
        XCTAssertTrue(photoCard.isHittable)
        XCTAssertGreaterThan(photoCard.frame.height, 200)
        let chat = app.staticTexts["聊聊下一程"]
        XCTAssertLessThan(heading.frame.minY, chat.frame.minY)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Home saved places cards"; attachment.lifetime = .keepAlways
        add(attachment)
        photoCard.tap()
        XCTAssertTrue(app.buttons["close-marker-detail"].waitForExistence(timeout: 5))
    }

    @MainActor func testUnplannedUsesRoutePlaceLayoutWithoutSchedule() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--day-detail-style-preview", "--day-chain-layout-preview", "--inline-address-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 10))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        trip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1)); day.tap()
        let unplanned = app.buttons["day-marker-demo-3"].firstMatch
        XCTAssertTrue(unplanned.waitForExistence(timeout: 5))
        for _ in 0..<6 where !unplanned.isHittable { app.swipeUp() }
        XCTAssertTrue(unplanned.isHittable)
        XCTAssertTrue(app.staticTexts["day-address-demo-3"].exists)
        let cover = app.descendants(matching: .any)["day-cover-demo-3"].firstMatch
        XCTAssertTrue(cover.exists)
        XCTAssertEqual(cover.frame.height, 140, accuracy: 1)
        XCTAssertGreaterThan(cover.frame.width, cover.frame.height)
        XCTAssertFalse(app.buttons["day-schedule-demo-3"].exists)
        XCTAssertEqual(unplanned.value as? String, "")
    }

    @MainActor func testEditingHidesRouteCountAndActions() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--day-chain-layout-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let heading = app.descendants(matching: .any)["route-heading-0"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(heading.label.contains("个地点"))
        XCTAssertTrue(app.buttons["route-actions-0"].exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        let point = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: heading.frame.midX, dy: heading.frame.midY))
        point.press(forDuration: 0.8)
        XCTAssertFalse(app.buttons["day-edit-done"].exists)
        app.buttons["route-actions-0"].tap()
        app.buttons["编辑行程"].tap()
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(heading.label.contains("个地点"))
        XCTAssertFalse(app.buttons["route-actions-0"].exists)
        XCTAssertTrue(app.buttons["route-toggle-0"].exists)
        app.buttons["day-edit-done"].tap()
        XCTAssertTrue(app.buttons["route-actions-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(heading.label.contains("个地点"))
    }

    @MainActor func testRouteHeadingIsDisplayOnlyAndAllowsScrolling() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--trip-places-preview", "--day-chain-layout-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let heading = app.descendants(matching: .any)["route-heading-0"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertFalse(app.buttons["route-heading-0"].exists)
        let originalY = heading.frame.minY
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: heading.frame.midX, dy: heading.frame.midY)).tap()
        XCTAssertEqual(heading.frame.minY, originalY, accuracy: 3)
        let toggle = app.buttons["route-toggle-0"]
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "已收起")
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: heading.frame.midX, dy: heading.frame.midY)).tap()
        XCTAssertEqual(toggle.value as? String, "已收起")
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "已展开")
        let title = app.buttons["route-0-marker-demo-1"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let titleY = title.frame.minY
        let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: heading.frame.minX + heading.frame.width * 0.3, dy: heading.frame.midY))
        start.press(forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -120)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertLessThan(title.frame.minY, titleY - 20, "Dragging the route heading must scroll the list")
        XCTAssertFalse(app.buttons["day-edit-done"].exists)
    }

    @MainActor func testDayCoverIsDisplayOnlyAndScrolls() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--journey-card-style-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 10)); trip.tap()
        let day = app.buttons["journey-day-day-2"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8)); day.tap()
        let title = app.buttons["route-0-marker-demo-3"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        // The cover begins below the title/address header and is 140pt high.
        func coverPoint() -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: title.frame.midX, dy: title.frame.maxY + 70))
        }
        attach(app, "Cover scroll before")
        let before = title.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.65)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.40)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertLessThan(title.frame.minY, before - 30)
        XCTAssertFalse(app.buttons["day-edit-done"].exists)
        attach(app, "Cover scroll up")
        let after = title.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.40)).press(forDuration: 0.01, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.65)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertGreaterThan(title.frame.minY, after + 30)
        coverPoint().tap()
        XCTAssertTrue(app.buttons["close-marker-detail"].waitForExistence(timeout: 5))
        app.buttons["close-marker-detail"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        app.buttons["route-actions-0"].tap()
        app.buttons["编辑行程"].tap()
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        let selection = app.buttons["route-0-select-demo-3"]
        XCTAssertTrue(selection.waitForExistence(timeout: 3))
        XCTAssertEqual(selection.value as? String, "未选中", "长按松手不能顺带选中地点")
        selection.tap()
        XCTAssertEqual(selection.value as? String, "已选中")
        selection.tap()
        XCTAssertEqual(selection.value as? String, "未选中")
        app.buttons["day-edit-done"].tap()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        title.tap()
        XCTAssertTrue(app.buttons["close-marker-detail"].waitForExistence(timeout: 5))
    }
    @MainActor func testHomeHistoryButtonPaddingIsTappable() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--archive-ai-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let history = app.buttons["archive-chat-history"]
        XCTAssertTrue(history.waitForExistence(timeout: 5))
        for _ in 0..<4 where !history.isHittable { app.swipeUp() }
        XCTAssertGreaterThanOrEqual(history.frame.height, 44)
        history.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.1)).tap()
        XCTAssertTrue(app.scrollViews["ai-conversation-list"].waitForExistence(timeout: 3))
    }
    @MainActor func testChatEdgeSwipeReturnsHome() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--archive-ai-preview", "--fullscreen-chat-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let recent = app.buttons["archive-chat-recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); recent.tap()
        XCTAssertTrue(app.buttons["ai-close"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ai-close"].label, "返回")
        attach(app, "AI bare back arrow")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45)))
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["ai-close"].exists)
    }
    @MainActor func testFullScreenChatReadingKeyboardAndHistory() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--archive-ai-preview", "--fullscreen-chat-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let recent = app.buttons["archive-chat-recent"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5)); recent.tap()
        XCTAssertTrue(app.buttons["ai-close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["archive-chat-history"].isHittable)
        attach(app, "Full screen AI conversation")
        let input = app.descendants(matching: .any)["ai-message-input"].firstMatch
        input.tap(); input.typeText("交通方便的酒店就好。")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(app.buttons["ai-copy-answer"].isHittable)
        XCTAssertFalse(app.buttons["ai-jump-latest"].exists)
        attach(app, "Full screen AI keyboard")
        app.buttons["ai-conversations"].tap()
        XCTAssertTrue(app.scrollViews["ai-conversation-list"].waitForExistence(timeout: 3))
        attach(app, "Full screen AI conversation history")
        app.buttons["京都的四天慢旅行"].tap()
        let list = app.scrollViews["ai-message-list"]
        list.swipeDown(); list.swipeDown()
        XCTAssertTrue(app.buttons["ai-jump-latest"].waitForExistence(timeout: 3))
        let process = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "工具过程")).firstMatch
        XCTAssertTrue(process.isHittable)
        process.tap()
        XCTAssertTrue(app.staticTexts["搜索地点 · 已返回结果"].waitForExistence(timeout: 3))
        attach(app, "Full screen AI tool process")
        app.buttons["ai-close"].tap()
        XCTAssertTrue(recent.waitForExistence(timeout: 3))
    }
    @MainActor func testHomeKeyboardDismissal() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--archive-ai-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let input = app.textFields["archive-chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap(); input.typeText("京都")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertLessThan(input.frame.maxY, app.keyboards.firstMatch.frame.minY)
        attach(app, "Home keyboard with dismissal and background")
        XCTAssertFalse(app.buttons["archive-keyboard-dismiss"].exists)
        app.staticTexts["目的地、想做的事，或一个想法。"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertEqual(input.value as? String, "京都")
    }
    @MainActor func testHomeChatEntryZeroOneThreeAndHistory() {
        for variant in ["--empty-archive-preview", "--one-archive-preview", "--three-archive-preview"] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--archive-preview", "--archive-ai-preview", variant, "-AppleLanguages", "(zh-Hans)"]
            app.launch()
            let history = app.buttons["archive-chat-history"]
            XCTAssertTrue(history.waitForExistence(timeout: 5))
            for _ in 0..<4 where !history.isHittable { app.swipeUp() }
            XCTAssertTrue(history.isHittable)
            XCTAssertTrue(app.textFields["archive-chat-input"].isHittable)
            let settings = app.buttons["archive-settings"]
            for _ in 0..<4 where !settings.isHittable { app.swipeUp() }
            XCTAssertTrue(settings.isHittable)
            XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
            app.swipeUp()
            XCTAssertGreaterThan(settings.frame.midY, app.frame.height * 0.85,
                "设置应停在底部，不应因尾部空白继续向上滚动")
            attach(app, "Home AI " + variant)
            if variant == "--one-archive-preview" {
                let input = app.textFields["archive-chat-input"]
                input.tap(); input.typeText("想去京都，四天，慢一点。")
                XCTAssertTrue(app.buttons["archive-chat-send"].exists)
                attach(app, "Home AI plain send icon")
            }
            history.tap()
            XCTAssertTrue(app.scrollViews["ai-conversation-list"].waitForExistence(timeout: 3))
            app.buttons["京都的四天慢旅行"].tap()
            XCTAssertTrue(app.buttons["ai-close"].waitForExistence(timeout: 3))
            app.buttons["ai-close"].tap()
            XCTAssertTrue(history.waitForExistence(timeout: 3))
            app.terminate()
        }
    }
    @MainActor func testHomeChatConfigurationEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let input = app.textFields["archive-chat-input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["archive-chat-settings"].exists)
        input.tap(); input.typeText("想去京都")
        XCTAssertTrue(app.buttons["archive-chat-send"].isEnabled)
        app.buttons["archive-chat-send"].tap()
        XCTAssertTrue(app.alerts["AI 尚未配置"].waitForExistence(timeout: 5))
        app.alerts["AI 尚未配置"].buttons["取消"].tap()
        XCTAssertTrue(app.buttons["ai-close"].exists)
        XCTAssertEqual(app.textFields["ai-message-input"].value as? String, "想去京都")
        app.buttons["ai-close"].tap()
        XCTAssertEqual(input.value as? String, "想去京都")
    }
    @MainActor func testArchiveNumbersContinueIntoDetail() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(app.buttons["archive-settings"].frame.midY, app.frame.height * 0.8)
        XCTAssertEqual(card.staticTexts["archive-number-demo-trip"].label, "No. 001")
        attach(app, "Archive card automatic number")
        card.tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["archive-number-demo-trip"].firstMatch.label, "No. 001")
    }
    @MainActor func testEmptyArchiveUsesExistingCardsAndCreation() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--empty-archive-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let create = app.buttons["empty-archive-create"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["0 次旅途"].exists)
        XCTAssertFalse(app.staticTexts["把第一段旅途，放进这里。"].exists)
        attach(app, "Empty archive existing three-card stack")
        create.tap()
        XCTAssertTrue(app.textFields["trip-name-field"].waitForExistence(timeout: 5))
    }
    @MainActor func testDayThemeMenuAndCancel() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--journey-card-style-preview"]
        app.launch()
        let cover = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(cover.waitForExistence(timeout: 5)); cover.tap()
        let first = app.buttons["journey-day-day-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); sleep(1)
        first.swipeRight()
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑"].waitForExistence(timeout: 3))
        attach(app, "Day editor from right swipe")
        app.buttons["取消"].tap()
        first.press(forDuration: 1)
        app.buttons["编辑"].tap()
        XCTAssertTrue(app.navigationBars["编辑"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        let add = app.buttons["journey-add-day"]
        for _ in 0..<6 where !add.isHittable { app.swipeUp() }
        add.tap()
        XCTAssertTrue(app.navigationBars["添加一天"].waitForExistence(timeout: 3))
        let place = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'day-editor-place-'")).firstMatch
        XCTAssertTrue(place.exists)
        XCTAssertEqual(place.value as? String, "未选")
        place.tap()
        XCTAssertEqual(place.value as? String, "已选")
        attach(app, "Add day optional theme and trip places")
        app.buttons["取消"].tap()
    }

    @MainActor func testChapterDeletionDesign() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview"]
        app.launch()
        app.buttons["archive-trip-demo-trip"].tap()
        let menu = app.buttons["journey-day-menu-day-1"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); sleep(1); menu.tap()
        app.buttons["删除"].tap()
        let choice = app.buttons["delete-day-markers"]
        XCTAssertTrue(choice.waitForExistence(timeout: 3))
        XCTAssertEqual(choice.value as? String, "未选")
        choice.tap()
        XCTAssertEqual(choice.value as? String, "已选")
        attach(app, "Chapter deletion confirmation")
        app.buttons["取消"].tap()
        XCTAssertTrue(menu.exists)
    }

    @MainActor func testDayEditorErrorUsesChapterPanelAndPreservesDraft() {
        let app = XCUIApplication(); app.launchArguments = ["--demo", "--archive-preview"]
        app.launch(); app.buttons["archive-trip-demo-trip"].tap()
        let menu = app.buttons["journey-day-menu-day-1"]
        XCTAssertTrue(menu.waitForExistence(timeout: 5)); sleep(1); menu.tap()
        app.buttons["编辑"].tap()
        let submit = app.buttons["day-editor-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5)); submit.tap()
        XCTAssertTrue(app.buttons["知道了"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 0)
        app.buttons["知道了"].tap()
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }

    @MainActor func testContinuousDayChapters() {
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--journey-card-style-preview"]
            if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            let cover = app.buttons["archive-trip-demo-trip"]
            XCTAssertTrue(cover.waitForExistence(timeout: 5))
            cover.tap()
            let first = app.buttons["journey-day-day-1"]
            XCTAssertTrue(first.waitForExistence(timeout: 5))
            XCTAssertTrue(first.label.contains("第1天"))
            XCTAssertTrue(first.label.contains("09:30 首站"))
            XCTAssertFalse(first.label.contains("地铁"))
            sleep(2)
            attach(app, large ? "Chapters large type" : "Chapters first day")
            let second = app.buttons["journey-day-day-2"]
            for _ in 0..<6 where !second.isHittable { app.swipeUp() }
            XCTAssertTrue(second.isHittable)
            XCTAssertTrue(second.label.contains("第2天"))
            attach(app, large ? "Untitled chapter large type" : "Untitled chapter")
            second.tap()
            XCTAssertTrue(app.buttons["day-detail-date-day-1"].waitForExistence(timeout: 5))
            app.terminate()
        }
    }

    @MainActor func testDayCardsAndPhotoArchive() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--journey-card-style-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        // Local fixture photos must be decoded before exercising the snapshot transition.
        sleep(3)
        attach(app, "Native journey home")
        let initialY = card.frame.minY
        card.tap()
        let first = app.buttons["journey-day-day-1"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(first.label.contains("09:30 首站"))
        XCTAssertFalse(first.label.contains("地铁"))
        XCTAssertTrue(first.label.contains("第1天"))
        sleep(1)
        attach(app, "Native day cards with photos")
        first.swipeUp()
        attach(app, "Native day cards no theme and empty day")
        for _ in 0..<5 where !app.buttons["journey-edit-trip"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["journey-edit-trip"].isHittable)
        app.buttons["journey-edit-trip"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        for _ in 0..<5 where !first.isHittable { app.swipeDown() }
        first.tap()
        sleep(1)
        app.swipeUp()
        attach(app, "Native day action capsules")
        XCTAssertTrue(app.buttons["day-search-add-place"].exists)
        app.buttons["新建路线"].tap()
        XCTAssertTrue(app.buttons["取消"].waitForExistence(timeout: 3))
        app.buttons["取消"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["archive-detail-close"].tap()
        XCTAssertTrue(app.buttons["archive-create"].waitForExistence(timeout: 5))
        XCTAssertEqual(card.frame.minY, initialY, accuracy: 2)
        let settings = app.buttons["archive-settings"]
        for _ in 0..<5 where !settings.isHittable { app.scrollViews["archive-trip-list"].swipeUp() }
        XCTAssertTrue(settings.isHittable)
        attach(app, "Archive footer settings entry")
        settings.tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 3))
    }
    @MainActor func testDayDetailVisualsAndEditors() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--route-distance-preview", "--day-detail-style-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let schedule = app.buttons["route-0-schedule-demo-0"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-detail-date-day-1"].exists)
        attach(app, "Day detail scheduled")
        XCTAssertTrue(app.staticTexts["沿街散步，看看老建筑。"].exists)
        schedule.tap()
        XCTAssertTrue(app.textFields["schedule-duration"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schedule-duration"].value as? String, "60")
        app.buttons["取消"].tap()
        app.otherElements["route-0-transport-0"].firstMatch.press(forDuration: 1)
        XCTAssertTrue(app.textFields["schedule-service"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["schedule-service"].value as? String, "10号线")
        app.buttons["取消"].tap()
        app.buttons["route-toggle-0"].tap()
        XCTAssertFalse(schedule.exists)
        attach(app, "Day detail collapsed")
        app.buttons["route-toggle-0"].tap()
        XCTAssertTrue(schedule.waitForExistence(timeout: 3))
    }
    @MainActor func testDayDetailLegacyAndLargeType() {
        for large in [false, true] {
            let app = XCUIApplication()
            app.launchArguments = ["--demo", "--archive-preview", "--route-distance-preview"]
            if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            let card = app.buttons["archive-trip-demo-trip"]
            XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
            let day = app.buttons["journey-day-day-1"]
            XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
            XCTAssertTrue(app.buttons["route-0-marker-demo-0"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.otherElements["route-0-transport-0"].firstMatch.exists)
            attach(app, large ? "Day detail accessibility type" : "Day detail legacy distance")
            app.terminate()
        }
    }
    @MainActor func testDayDetailLongNameAndUntitledHeader() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--transport-schedule-preview", "--day-detail-style-preview", "--day-detail-long-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        XCTAssertTrue(app.buttons["route-0-schedule-demo-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-marker-demo-3"].exists)
        let note = app.staticTexts["先到沿街入口集合，参观前核对预约时间；雨天从侧门进入，沿着连廊前往展厅。"]
        XCTAssertGreaterThan(note.frame.height, 20)
        attach(app, "Day detail long name without theme")
        app.buttons["route-0-marker-demo-0"].press(forDuration: 0.6)
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertFalse(note.exists)
        XCTAssertFalse(app.buttons["route-0-schedule-demo-0"].exists)
        XCTAssertFalse(app.otherElements["route-0-transport-0"].firstMatch.exists)
        XCTAssertLessThanOrEqual(app.buttons["day-selection-move"].frame.height, 48)
        XCTAssertLessThanOrEqual(app.buttons["route-0-marker-demo-0"].frame.height, 60)
        attach(app, "Day detail compact selection layout")
        app.buttons["day-edit-done"].tap()
        XCTAssertTrue(app.buttons["route-0-schedule-demo-0"].exists)
    }
    @MainActor func testDeletedDayMemberDoesNotShowEmptyUnscheduledGroup() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--day-stale-member-preview"]
        app.launch()
        app.buttons["archive-trip-demo-trip"].tap()
        XCTAssertFalse(app.buttons["archive-detail-map"].exists)
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9))
        day.tap()
        XCTAssertTrue(app.buttons["day-detail-date-day-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["route-0-marker-demo-2"].exists)
        XCTAssertFalse(app.staticTexts["未安排"].exists)
        XCTAssertFalse(app.buttons["day-marker-deleted-marker"].exists)
        attach(app, "Deleted member excluded; day has three actual places")
    }
    @MainActor func testUnscheduledPlacesStyle() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--trip-places-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5)); card.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        app.swipeUp()
        let place = app.buttons["trip-unscheduled-preview-cafe"]
        XCTAssertTrue(place.isHittable)
        XCTAssertTrue(app.buttons["trip-add-place"].exists)
        attach(app, "Unscheduled places and compact actions")
    }
    @MainActor private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

// Temporary diagnostic; removed after collecting evidence.
extension JourneyCardStyleUITests {
    @MainActor func testDiagnosisPhotoScroll() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--journey-card-style-preview", "-AppleLanguages", "(zh-Hans)"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"].firstMatch
        XCTAssertTrue(trip.waitForExistence(timeout: 10)); trip.tap()
        let day = app.buttons["journey-day-day-2"].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1)); day.tap()
        let title = app.buttons["route-0-marker-demo-3"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        func point(_ x: CGFloat, _ y: CGFloat) -> XCUICoordinate {
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
        }
        func shot(_ name: String) {
            let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
        }
        shot("Diagnosis initial")
        let before = title.frame.minY
        let photoY = title.frame.maxY + 75
        let x: CGFloat = 220
        print("PHOTO_DIAG before=\(before) photo=(\(x),\(photoY)) title=\(title.frame)")
        let cell = app.cells.containing(.button, identifier: "route-0-marker-demo-3").firstMatch
        print("PHOTO_DIAG cell=\(cell.frame)")
        cell.swipeUp(velocity: .fast)
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        print("PHOTO_DIAG afterPhoto=\(title.frame.minY) editing=\(app.buttons["day-edit-done"].exists)")
        shot("Diagnosis after photo drag")
        let textBefore = title.frame.minY
        title.swipeUp(velocity: .fast)
        RunLoop.current.run(until: Date().addingTimeInterval(0.7))
        print("PHOTO_DIAG textBefore=\(textBefore) afterText=\(title.frame.minY)")
        shot("Diagnosis after text drag")
    }
}
