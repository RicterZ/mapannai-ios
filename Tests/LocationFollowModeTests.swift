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
    func testPinchAndRotationDoNotBecomePanWhenOneFingerLifts() {
        do {
            var policy = LocationGesturePolicy()
            XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 0), .none)
            XCTAssertEqual(policy.update(active: true, transform: true, singlePanDistance: 20), .none)
            XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 40), .none)
            XCTAssertEqual(policy.update(active: false, transform: false, singlePanDistance: nil), .transformEnded)
            XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 12), .pan)
            XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 20), .none)
        }
    }
    func testSmallFingerMovementDoesNotStopTracking() {
        var policy = LocationGesturePolicy()
        XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 4), .none)
        XCTAssertEqual(policy.update(active: true, transform: false, singlePanDistance: 8), .pan)
    }
}
