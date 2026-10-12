import XCTest

final class JourneyEditorRedesignTests: XCTestCase {
    @MainActor private func launch(_ kind: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--editor-preview", kind, "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        return app
    }
    @MainActor private func capture(_ name: String) {
        // Let the system sheet finish presenting before taking review screenshots.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    @MainActor func testInlineArchiveTitleAndStableYearCardsReturnToSamePosition() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--year-archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let title = app.staticTexts["archive-page-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["我的旅途"].exists)
        let year = app.descendants(matching: .any)["archive-year-2025"].firstMatch
        XCTAssertTrue(year.exists)
        XCTAssertFalse(app.buttons["archive-year-2025"].exists)
        capture("我的旅途 · 页内标题与年度叠卡")
        let scroll = app.scrollViews["archive-trip-list"]
        scroll.swipeUp()
        let card = app.buttons["archive-trip-year-2024"]
        XCTAssertTrue(card.isHittable)
        let initialY = card.frame.minY
        capture("年度卡片 · 固定生成的不同配色图案")
        card.tap()
        XCTAssertTrue(app.buttons["archive-detail-close"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        app.buttons["archive-detail-close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertEqual(card.frame.minY, initialY, accuracy: 2)
        XCTAssertTrue(year.exists)
        capture("年度卡片 · 返回恢复原堆叠位置")
    }
    @MainActor func testPlaceActionsRemoveTodayAndCancelKeepsMembership() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--long-note-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let row = app.buttons["route-0-marker-demo-0"]
        XCTAssertTrue(row.waitForExistence(timeout: 5)); row.tap()
        let remove = app.buttons["remove-marker-from-current-day"]
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        let navigate = app.buttons["marker-navigate"], edit = app.buttons["edit-marker-detail"], delete = app.buttons["marker-delete"]
        XCTAssertLessThan(navigate.frame.maxX, edit.frame.minX)
        XCTAssertLessThan(edit.frame.maxX, remove.frame.minX)
        XCTAssertLessThan(remove.frame.maxX, delete.frame.minX)
        XCTAssertLessThanOrEqual(delete.frame.maxX, app.frame.width - 10)
        XCTAssertTrue(remove.isHittable)
        let itinerary = app.buttons["marker-itinerary-day-1"]
        XCTAssertGreaterThan(navigate.frame.minY, itinerary.frame.maxY)
        capture("地点详情 · 操作位于所属行程下方")
        remove.tap()
        XCTAssertTrue(app.alerts["从今日行程移除？"].waitForExistence(timeout: 5))
        capture("从今日移除 · 保留收藏和其他日期")
        app.alerts.buttons["取消"].tap()
        XCTAssertTrue(app.otherElements["marker-in-current-day"].exists || app.staticTexts["marker-in-current-day"].exists)
        XCTAssertTrue(remove.exists)
        app.buttons["close-marker-detail"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        let second = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(second.waitForExistence(timeout: 5)); second.tap()
        XCTAssertTrue(remove.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(app.staticTexts["笔记"].isHittable)
        capture("地点详情 · 半屏显示笔记正文")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertFalse(app.buttons["marker-navigate"].isHittable)
        capture("地点详情 · 顶部仅拖动条且按钮随内容滚动")
        app.buttons["close-marker-detail"].tap()
    }
    @MainActor func testArchivePullToRefreshKeepsCardNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let initialY = card.frame.minY
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.22))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        XCTAssertTrue(card.exists)
        XCTAssertEqual(card.frame.minY, initialY, accuracy: 4)
        capture("Home cards after pull to refresh")
        card.tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        app.buttons["archive-detail-close"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
    @MainActor func testTripIllustratedSVGIconPanel() {
        let app = launch("trip")
        let picker = app.buttons["trip-icon-picker"]
        XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        XCTAssertTrue(app.buttons["trip-icon-option-🇨🇳"].waitForExistence(timeout: 5))
        capture("Trip icon grid uses illustrated SVG artwork")
        app.buttons["trip-icon-option-🇨🇳"].tap()
        XCTAssertTrue(picker.label.contains("🇨🇳"))
        capture("Selected trip flag retains its stored emoji identity")
    }
    @MainActor func testArchiveLongPressOpensSharedTripEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let card = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.press(forDuration: 0.8)
        XCTAssertTrue(app.buttons["编辑旅途"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["删除旅途"].exists)
        capture("Trip long press actions")
        app.buttons["编辑旅途"].tap()
        XCTAssertTrue(app.textFields["trip-name-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trip-date-range"].exists)
        XCTAssertTrue(app.buttons["trip-create-submit"].exists)
        capture("Trip editor from long press")
        app.buttons["trip-create-cancel"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }
    @MainActor func testDayLongPressEditsInPlaceAndSwipeOffersTransfer() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 0.7)
        XCTAssertTrue(app.buttons["day-edit-done"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["route-view-0"].exists)
        XCTAssertFalse(app.buttons["save-chain-editor"].exists)
        capture("Day long press editing in place")
        XCTAssertTrue(app.buttons["day-selection-copy"].isEnabled)
        app.buttons["day-selection-copy"].tap()
        XCTAssertTrue(app.buttons["transfer-day-day-2"].waitForExistence(timeout: 5))
        app.buttons["transfer-day-day-2"].tap()
        XCTAssertTrue(app.buttons["transfer-day-submit"].isEnabled)
        capture("Copy selected places to a day")
        app.buttons["transfer-day-cancel"].tap()
        XCTAssertTrue(app.buttons["transfer-day-cancel"].waitForNonExistence(timeout: 3))
        app.buttons["day-edit-done"].tap()
        XCTAssertFalse(app.buttons["day-edit-done"].exists)
        let cell = app.cells.containing(.button, identifier: "route-0-marker-demo-1").firstMatch
        cell.swipeRight()
        XCTAssertTrue(app.buttons["day-move-demo-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-copy-demo-1"].exists)
        XCTAssertTrue(app.buttons["day-delete-demo-1"].exists)
        capture("Place right swipe move copy delete")
        app.buttons["day-move-demo-1"].tap()
        XCTAssertTrue(app.buttons["transfer-day-day-2"].waitForExistence(timeout: 5))
        capture("Move a place to another day")
        app.buttons["transfer-day-cancel"].tap()
    }
    @MainActor func testSearchOpensAsSheetAndKeepsDraftInItsNavigation() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--paged-search-demo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        capture("Place search popup above the map")
        search.tap(); search.typeText("咖啡\n")
        let result = app.buttons["add-search-place-paged-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        capture("Place search popup results")
        result.tap()
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        app.buttons["cancel-marker-editor"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.value as? String, "咖啡")
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["route-view-0"].waitForExistence(timeout: 5))
    }
    @MainActor func testDayListPlaceOpensHalfDetailAndRestoresFullAndHalfDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let handle = app.buttons["面板高度"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let row = app.buttons["route-0-marker-demo-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        for index in 0..<2 {
            let originalY = handle.frame.minY
            row.tap()
            let close = app.buttons["close-marker-detail"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.45)
            XCTAssertLessThan(close.frame.minY, app.frame.height * 0.65)
            XCTAssertTrue(app.buttons["marker-detail-location"].waitForExistence(timeout: 5))
            capture(index == 0 ? "Full day list opens half place detail" : "Half day list opens half place detail")
            if index == 0 {
                app.buttons["edit-marker-detail"].tap()
                XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["marker-coordinate-disclosure"].exists)
                XCTAssertFalse(app.textFields["纬度"].exists)
                XCTAssertFalse(app.textFields["经度"].exists)
                capture("Place editor shows address without coordinate controls")
                app.buttons["cancel-marker-editor"].tap()
                XCTAssertTrue(close.waitForExistence(timeout: 5))
            }
            close.coordinate(withNormalizedOffset: CGVector(dx: 0.12, dy: 0.5)).tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            RunLoop.current.run(until: Date().addingTimeInterval(0.6))
            XCTAssertEqual(handle.frame.minY, originalY, accuracy: 4)
            if index == 1 {
                XCTAssertTrue(app.buttons["itinerary-search"].waitForExistence(timeout: 5))
                XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
                XCTAssertLessThan(app.buttons["itinerary-search"].frame.maxY, handle.frame.minY)
            }
            capture(index == 0 ? "Returning restores full day list" : "Returning restores half day list")
            if index == 0 {
                handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.56)))
                RunLoop.current.run(until: Date().addingTimeInterval(0.5))
                XCTAssertGreaterThan(handle.frame.minY, app.frame.height * 0.4)
                XCTAssertLessThan(handle.frame.minY, app.frame.height * 0.65)
            }
        }
        row.press(forDuration: 0.7)
        let done = app.buttons["day-edit-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(done.frame.midX, app.frame.width * 0.75)
        XCTAssertLessThan(done.frame.minY, row.frame.minY)
        capture("Day editing finishes with top right checkmark")
        done.tap()
        XCTAssertTrue(done.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists)
        capture("Finishing edit restores the regular day list")
    }
    @MainActor func testMapSelectionFromExpandedSearchRestoresPreviousHeight() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-marker:demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["edit-marker-detail"].exists)
        XCTAssertTrue(app.buttons["marker-delete"].exists)
        XCTAssertTrue(app.buttons["marker-itinerary-day-2"].exists)
        XCTAssertTrue(app.staticTexts["上海市"].exists)
        capture("搜索已保存地点 · 复用地点详情")
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        app.buttons["cancel-marker-editor"].tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let halfY = search.frame.minY
        let pin = app.buttons["saved/demo-3"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.frame.minY, halfY, accuracy: 4)
        let handle = app.buttons["面板高度"].firstMatch
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.16)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let fullY = search.frame.minY
        XCTAssertLessThan(fullY, halfY - 100)
        capture("Expanded search before selecting a map marker")
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["search-detail-back"].waitForExistence(timeout: 5))
        capture("Map marker opens place details from expanded search")
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(search.frame.minY, fullY, accuracy: 4)
        capture("Returning restores the expanded search height")
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["route-view-0"].waitForExistence(timeout: 5))
    }
    @MainActor func testSearchMapPreviewDoesNotAddAndLongPressCancelKeepsNamedRow() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["add-place-result-saved-demo-3"].exists)
        XCTAssertFalse(app.staticTexts["添加到今日行程"].exists)
        capture("附近已保存地点 · 白底结果列表")
        search.tap(); search.typeText("静安\n")
        let result = app.buttons["add-place-result-marker:demo-3"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        XCTAssertTrue(app.buttons["search-detail-add"].waitForExistence(timeout: 5))
        capture("Saved place preview still offers explicit join")
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let pin = app.buttons["saved/demo-3"]
        XCTAssertTrue(pin.waitForExistence(timeout: 5))
        pin.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["search-detail-add"].waitForExistence(timeout: 5))
        app.buttons["search-detail-back"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        let handle = app.buttons["面板高度"].firstMatch
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(search.frame.minY, app.frame.height * 0.75)
        XCTAssertFalse(app.buttons["route-view-0"].isHittable)
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        let input = app.searchFields["map-place-search"]
        let panel = app.otherElements["edge-attached-panel"].firstMatch
        XCTAssertGreaterThanOrEqual(app.buttons["close-place-picker"].frame.minY, panel.frame.minY)
        XCTAssertLessThan(input.frame.maxY - panel.frame.minY, 80)
        capture("搜索最小档 · 裸搜索框与返回")
        app.buttons["close-place-picker"].coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.42)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        XCTAssertLessThan(search.frame.minY, app.frame.height * 0.7)
        XCTAssertEqual(search.value as? String, "静安")
        capture("搜索上拉 · 恢复白底结果面板")
        search.tap(); search.typeText("\n")
        XCTAssertTrue(app.buttons["add-place-result-marker:demo-3"].waitForExistence(timeout: 5))
        let map = app.otherElements["map-canvas"].firstMatch
        let point = (map.exists ? map : app).coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        point.press(forDuration: 0.9)
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        app.buttons["cancel-marker-editor"].tap()
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["地图选点"].exists)
        XCTAssertEqual(search.value as? String, "静安")
        capture("Long press cancel retains a visible named place")
    }
    @MainActor func testArchiveSearchPopupHandsOffMapAndRestoresSearch() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--paged-search-demo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        let add = app.buttons["day-search-add-place"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        if !add.isHittable { app.swipeUp() }
        add.tap()
        let search = app.searchFields["map-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("咖啡\n")
        let result = app.buttons["add-place-result-paged-0"]
        XCTAssertTrue(result.waitForExistence(timeout: 5)); result.tap()
        let back = app.buttons["search-detail-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 8)); back.tap()
        XCTAssertTrue(search.waitForExistence(timeout: 8))
        XCTAssertEqual(search.value as? String, "咖啡")
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["route-view-0"].waitForExistence(timeout: 5))
    }
    @MainActor func testDayMapEntryShowsJourneyChainAndActionsFit() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        for action in [app.buttons["day-search-add-place"], app.buttons["新建路线"], app.buttons["day-edit-places"]] {
            XCTAssertTrue(action.exists)
            XCTAssertGreaterThanOrEqual(action.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(action.frame.maxX, app.frame.maxX)
        }
        capture("Day actions fit screen")
        app.buttons["archive-day-map"].tap()
        let controls = app.otherElements["day-map-journey"]
        XCTAssertTrue(controls.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["itinerary-search"].exists)
        XCTAssertFalse(app.buttons["day-search-add-place"].isHittable)
        XCTAssertFalse(app.buttons["journey-back"].exists)
        capture("Day map entry compact panel")
        app.buttons["itinerary-search"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.searchFields["map-place-search"].waitForExistence(timeout: 5))
        app.buttons["close-place-picker"].tap()
        XCTAssertTrue(app.buttons["close-map-workspace"].waitForExistence(timeout: 5))
        app.buttons["close-map-workspace"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        app.buttons["archive-day-close"].tap()
        XCTAssertTrue(app.buttons["archive-detail-close"].waitForExistence(timeout: 5))
    }
    @MainActor func testDayMapShowsHorizontalChainAndKeepsManualCamera() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview", "--delayed-route-distance-preview", "--inline-address-preview", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5)); day.tap()
        XCTAssertTrue(app.staticTexts["map-day-trip-title"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["archive-day-map"].exists)
        let initialHandle = app.buttons["面板高度"]
        initialHandle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)))
        let chain = app.scrollViews["day-map-chain"]
        XCTAssertTrue(chain.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.otherElements["day-map-journey"].frame.height, app.frame.height * 0.25)
        XCTAssertLessThanOrEqual(app.buttons["day-map-stop-demo-0"].frame.height, 96)
        XCTAssertFalse(app.otherElements["compact-journey-controls"].exists)
        let first = app.buttons["day-map-stop-demo-0"]
        XCTAssertTrue(first.isHittable)
        XCTAssertGreaterThanOrEqual(first.frame.minX, 0)
        XCTAssertLessThan(first.frame.maxX, app.frame.width - 80)
        RunLoop.current.run(until: Date().addingTimeInterval(1.4))
        capture("Day map horizontal chain initial overview")
        chain.swipeLeft()
        XCTAssertTrue(app.buttons["day-map-stop-demo-1"].waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        capture("Day map chain second focused place")
        let map = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
        map.press(forDuration: 0.1, thenDragTo: map.withOffset(CGVector(dx: 90, dy: 0)))
        chain.swipeLeft()
        capture("Day map chain after manual map movement")
        XCTAssertTrue(app.buttons["itinerary-header-location"].exists)
        XCTAssertFalse(app.buttons["day-map-fit"].exists)
        let handle = app.buttons["面板高度"]
        XCTAssertTrue(handle.exists)
        app.buttons["day-map-date-day-1"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.40)))
        XCTAssertTrue(app.otherElements["phone-itinerary-panel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-detail-date-day-1"].exists)
        XCTAssertTrue(app.staticTexts["map-day-trip-title"].isHittable)
        XCTAssertGreaterThan(app.staticTexts["map-day-trip-title"].frame.height, 15)
        let titleTop = app.staticTexts["map-day-trip-title"].frame.minY
        let panelTop = app.otherElements["edge-attached-panel"].firstMatch.frame.minY
        XCTAssertLessThanOrEqual(titleTop - panelTop, 20)
        XCTAssertFalse(app.buttons["map-day-close"].exists)
        XCTAssertFalse(app.buttons["map-day-map"].exists)
        let panel = app.otherElements["edge-attached-panel"].firstMatch
        XCTAssertGreaterThan(panel.frame.minY - app.buttons["itinerary-search"].frame.maxY, 8)
        capture("Day map expanded daily detail half height")
        handle.tap()
        capture("Day map expanded daily detail full height")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)))
        XCTAssertTrue(chain.waitForExistence(timeout: 5))
        capture("Day map collapsed back to chain")
        app.buttons["close-map-workspace"].tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
    }
    @MainActor func testDayMapTopEditOpensTripEditorAndBackReturnsTrip() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let edit = app.buttons["day-map-edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        let home = app.buttons["day-map-back"]
        XCTAssertTrue(home.exists)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let panel = app.otherElements["phone-itinerary-panel"]
        XCTAssertLessThan(edit.frame.maxY, panel.frame.minY)
        XCTAssertLessThan(home.frame.maxY, panel.frame.minY)
        XCTAssertFalse(app.buttons["day-edit-places"].exists)
        capture("Day map top home and edit controls")
        // UIKit custom presentations misreport background isHittable; exercise real touch routing.
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.textFields["trip-name-field"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["trip-date-range"].exists)
        XCTAssertFalse(app.buttons["day-edit-done"].exists)
        capture("Top edit opens shared trip title and date editor")
        app.buttons["trip-create-cancel"].tap()
        home.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.buttons["journey-day-day-1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["archive-detail-close"].exists)
        XCTAssertFalse(app.buttons["archive-create"].exists)
        capture("Day map back returns to its trip detail")
    }
    @MainActor func testMarkerDetailIsHalfHeightAndDragDownRestoresDay() {
        let app = XCUIApplication()
        app.launchArguments = ["--demo", "--archive-preview"]
        app.launch()
        let trip = app.buttons["archive-trip-demo-trip"]
        XCTAssertTrue(trip.waitForExistence(timeout: 5)); trip.tap()
        let day = app.buttons["journey-day-day-1"]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(0.9)); day.tap()
        let handle = app.buttons["面板高度"]
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.94)))
        let marker = app.buttons["saved/demo-1"]
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        marker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let close = app.buttons["close-marker-detail"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(close.frame.minY, app.frame.height * 0.45)
        XCTAssertLessThan(close.frame.minY, app.frame.height * 0.65)
        XCTAssertTrue(app.buttons["marker-navigate"].exists)
        XCTAssertTrue(app.buttons["edit-marker-detail"].exists)
        let location = app.buttons["marker-detail-location"]
        XCTAssertTrue(location.exists)
        XCTAssertLessThan(location.frame.maxY, close.frame.minY)
        capture("Redesigned saved place detail half height")
        app.buttons["edit-marker-detail"].tap()
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        app.buttons["cancel-marker-editor"].tap()
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.18)))
        capture("Redesigned place detail expanded")
        handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.97)))
        XCTAssertTrue(close.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["day-map-stop-demo-0"].waitForExistence(timeout: 5))
        capture("Place drag down restores compact day")
    }
    @MainActor func testTripEditingSharesRangeAndRejectsShorterDates() {
        let app = launch("trip")
        let name = app.textFields["trip-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "上海 · 秋日散步")
        XCTAssertFalse(app.textFields["trip-destination-search"].exists)
        let save = app.buttons["trip-create-submit"]
        XCTAssertTrue(save.isEnabled)
        capture("Edit trip shared layout")
        app.buttons["trip-date-range"].tap()
        let fifth = app.buttons["trip-range-day-2026-10-05"]
        XCTAssertTrue(fifth.waitForExistence(timeout: 5)); fifth.tap(); fifth.tap()
        XCTAssertFalse(save.isEnabled)
        XCTAssertTrue(app.staticTexts["trip-minimum-days-error"].exists)
        fifth.tap(); app.buttons["trip-range-day-2026-10-08"].tap()
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.staticTexts["trip-date-summary"].label.contains("4 天"))
        capture("Edit trip extended date range")
        app.buttons["trip-range-done"].tap()
        XCTAssertTrue(save.isEnabled)
        app.buttons["trip-create-cancel"].tap()
    }
    @MainActor func testAddPlaceFieldsAndIconPanel() {
        let app = launch("place-add")
        let name = app.textFields["marker-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertEqual(name.value as? String, "京都站")
        XCTAssertTrue(app.buttons["save-marker-editor"].isEnabled)
        capture("Add place main fields")
        app.buttons["marker-icon-picker"].tap()
        XCTAssertTrue(app.buttons["marker-icon-option-transit"].waitForExistence(timeout: 3))
        capture("Place category icon panel")
        app.buttons["marker-icon-option-transit"].tap()
        XCTAssertTrue(app.buttons["marker-icon-picker"].label.contains("交通"))
        let scroll = app.scrollViews["marker-editor-scroll"]
        scroll.swipeUp()
        XCTAssertTrue(app.buttons["marker-note-editor"].isHittable)
        capture("Add place cover and note")
        app.buttons["cancel-marker-editor"].tap()
    }
    @MainActor func testNewPlaceRequiresNameAndCanEditCoordinates() {
        let app = launch("place-new")
        let name = app.textFields["marker-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["save-marker-editor"].isEnabled)
        capture("New place empty draft")
        name.tap(); name.typeText("街角咖啡")
        XCTAssertTrue(app.buttons["save-marker-editor"].isEnabled)
        app.buttons["cancel-marker-editor"].tap()
    }
    @MainActor func testEditPlacePreservesCoverAndNoteEntry() {
        let app = launch("place-edit")
        XCTAssertTrue(app.textFields["marker-name-field"].waitForExistence(timeout: 5))
        capture("Edit place main fields")
        app.scrollViews["marker-editor-scroll"].swipeUp()
        XCTAssertTrue(app.buttons["marker-note-editor"].isHittable)
        capture("Edit place cover and notes")
        app.buttons["marker-note-editor"].tap()
        XCTAssertTrue(app.navigationBars["编写笔记"].waitForExistence(timeout: 5))
        app.buttons["退出笔记编辑"].tap()
        XCTAssertTrue(app.buttons["cancel-marker-editor"].waitForExistence(timeout: 3))
        app.buttons["cancel-marker-editor"].tap()
    }
    @MainActor func testNewRouteAddsOrderedPlacesAndKeepsDraftOnCancel() {
        let app = launch("route-create")
        let save = app.buttons["save-chain-editor"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertFalse(save.isEnabled)
        capture("New route empty selection")
        app.buttons["chain-add-marker-demo-0"].tap()
        XCTAssertTrue(save.isEnabled)
        app.buttons["chain-add-marker-demo-1"].tap()
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(app.otherElements["chain-selected-demo-0"].exists || app.staticTexts["chain-selected-demo-0"].exists)
        capture("New route selected places")
        app.buttons["cancel-chain-editor"].tap()
        XCTAssertFalse(save.exists)
    }
    @MainActor func testEditRouteShowsExistingOrderAndCandidateSearch() {
        let app = launch("route-edit")
        let save = app.buttons["save-chain-editor"]
        XCTAssertTrue(save.waitForExistence(timeout: 5)); XCTAssertTrue(save.isEnabled)
        capture("Edit route order and remaining places")
        let search = app.textFields["chain-candidate-search"]
        if !search.isHittable { app.collectionViews["chain-editor-list"].swipeUp() }
        XCTAssertTrue(search.isHittable)
        search.tap(); search.typeText("无匹配的地点")
        XCTAssertTrue(app.staticTexts["没有匹配的地点"].exists)
        app.buttons["cancel-chain-editor"].tap()
    }
}
