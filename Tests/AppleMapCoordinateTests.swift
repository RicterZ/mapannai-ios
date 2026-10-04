import XCTest
import MapKit
@testable import MapAnNai

final class AppleMapCoordinateTests: XCTestCase {
    @MainActor func testShanghaiRenderAndTapRoundtrip() {
        let source = Coordinate(latitude: 31.2304, longitude: 121.4737)
        let displayed = AppleMapRenderer.Pin.coordinate(source)
        let expected = Coordinates.gcj(source)
        XCTAssertEqual(displayed.latitude, expected.latitude)
        XCTAssertEqual(displayed.longitude, expected.longitude)
        let restored = AppleMapRenderer.Coordinator.internalCoordinate(displayed)
        XCTAssertLessThan(Coordinates.distance(source, restored), 3)
    }
    @MainActor func testTokyoRemainsUnchanged() {
        let source = Coordinate(latitude: 35.6812, longitude: 139.7671)
        let displayed = AppleMapRenderer.Pin.coordinate(source)
        XCTAssertEqual(displayed.latitude, source.latitude)
        XCTAssertEqual(displayed.longitude, source.longitude)
        XCTAssertEqual(AppleMapRenderer.Coordinator.internalCoordinate(displayed), source)
    }
}
