import XCTest
@testable import MapAnNai

final class CameraMotionTests: XCTestCase {
    private let shanghai = Coordinate(latitude: 31.2304, longitude: 121.4737)
    func testNearbyFlightIsSlowerThanOldDefaultAndLongFlightGetsMoreTime() {
        let nearby = Coordinate(latitude: 31.235, longitude: 121.48)
        let beijing = Coordinate(latitude: 39.9042, longitude: 116.4074)
        let near = CameraMotion.duration(from: shanghai, to: nearby, currentZoom: 15, targetZoom: 15, reduceMotion: false)
        let far = CameraMotion.duration(from: shanghai, to: beijing, currentZoom: 15, targetZoom: 15, reduceMotion: false)
        XCTAssertEqual(near, 0.7, accuracy: 0.001)
        XCTAssertEqual(far, 1.1, accuracy: 0.001)
        XCTAssertGreaterThan(far, near)
    }
    func testZoomChangeAndRouteFramingHaveTimeToSettle() {
        let normal = CameraMotion.duration(from: shanghai, to: shanghai, currentZoom: 15, targetZoom: 15, reduceMotion: false)
        let zoom = CameraMotion.duration(from: shanghai, to: shanghai, currentZoom: 5, targetZoom: 15, reduceMotion: false)
        XCTAssertGreaterThan(zoom, normal)
        let fit = CameraMotion.duration(from: shanghai, to: shanghai, currentZoom: 15, targetZoom: nil, fitting: true, reduceMotion: false)
        XCTAssertEqual(fit, 0.9, accuracy: 0.001)
        let far = Coordinate(latitude: 40, longitude: -73)
        let longest = CameraMotion.duration(from: shanghai, to: far, currentZoom: 3, targetZoom: 20, reduceMotion: false)
        XCTAssertLessThanOrEqual(longest, 1.4)
    }
    func testReducedMotionSkipsBothFlightAndFramingAnimation() {
        for fitting in [false, true] {
            XCTAssertEqual(CameraMotion.duration(from: shanghai, to: Coordinate(latitude: 40, longitude: -73),
                currentZoom: 3, targetZoom: 15, fitting: fitting, reduceMotion: true), 0)
        }
    }
}
