import XCTest
@testable import MapAnNai

final class SearchSelectionTests: XCTestCase {
    @MainActor func testSelectionKeepsSearchAndRepeatedMapTapExpandsSameDraft() throws {
        let store = AppStore(settings: Settings(), demo: true)
        let place = Place(id: "result", name: "测试", address: "地址", coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        store.searchText = "测试"; store.searchResults = [place]
        store.choose(place)
        XCTAssertEqual(store.searchText, "测试"); XCTAssertEqual(store.searchResults, [place])
        XCTAssertFalse(store.draftExpanded)
        let draftID = try XCTUnwrap(store.draft?.id)
        store.draft?.title = "我输入的名称"
        let cameraID = store.camera?.id
        store.choose(place, fromMap: true)
        XCTAssertTrue(store.draftExpanded)
        XCTAssertEqual(store.draft?.id, draftID)
        XCTAssertEqual(store.draft?.title, "我输入的名称")
        XCTAssertEqual(store.camera?.id, cameraID)
        store.draft = nil
        store.choose(place, fromMap: true)
        XCTAssertFalse(store.draftExpanded)
        XCTAssertNotEqual(store.draft?.id, draftID)
        store.clearSearch()
        XCTAssertTrue(store.searchResults.isEmpty); XCTAssertNil(store.selectedSearchPlaceID)
    }
    @MainActor func testDemoSearchShowsAllMatchingReadOnlyPlaces() async {
        let store = AppStore(settings: Settings(), demo: true)
        store.searchText = "武康"
        await store.search()
        XCTAssertEqual(store.searchResults.map(\.name), ["武康大楼", "武康庭"])
        XCTAssertEqual(store.camera?.points.count, 2)
        XCTAssertEqual(store.searchText, "武康")
    }
}
