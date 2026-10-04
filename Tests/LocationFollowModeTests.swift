import XCTest
@testable import MapAnNai
final class LocationFollowModeTests: XCTestCase {
    @MainActor func testThreeClicksAndMapInteractionReset() {
        let store = AppStore(settings: Settings(), demo: true)
        XCTAssertEqual(store.locationMode.symbol, "location")
        store.cycleLocationMode(); XCTAssertEqual(store.locationMode, .centered)
        store.cycleLocationMode(); XCTAssertEqual(store.locationMode, .heading)
        XCTAssertEqual(store.locationMode.symbol, "location.fill")
        store.cycleLocationMode(); XCTAssertEqual(store.locationMode, .centered)
        XCTAssertEqual(store.locationMode.symbol, "location")
        store.noteMapInteraction(); XCTAssertEqual(store.locationMode, .idle)
    }
}
