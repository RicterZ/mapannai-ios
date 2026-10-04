import XCTest
@testable import MapAnNai

final class GoogleMapIntegrationTests: XCTestCase {
    func testGoogleKeyHandlesEmptyAndUnexpandedBuildSetting() {
        XCTAssertEqual(AppConfiguration.googleMapsKey(in: [:]), "")
        XCTAssertEqual(AppConfiguration.googleMapsKey(in: ["GoogleMapsIOSKey": "$(GOOGLE_MAPS_IOS_KEY)"]), "")
        XCTAssertEqual(AppConfiguration.googleMapsKey(in: ["GoogleMapsIOSKey": "  test-key \n"]), "test-key")
    }
    @MainActor func testNavigationKeepsStoredCoordinatesAndNeedsNoKey() throws {
        let marker = Marker(id: "test", coordinates: Coordinate(latitude: 31.2304, longitude: 121.4737), content: MarkerContent(id: "test", title: "地点 & 咖啡", iconType: .food, markdownContent: ""))
        let url = try XCTUnwrap(MarkerPresentation.googleNavigationURL(for: marker))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "www.google.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["api"], "1")
        XCTAssertEqual(items["destination"], "31.2304,121.4737")
        XCTAssertEqual(items["dir_action"], "navigate")
    }
    @MainActor func testSharedSelectedArtworkIsDistinctAndCached() throws {
        let normal = MapMarkerAppearance.image(icon: .food, compact: false, selected: false)
        let selected = MapMarkerAppearance.image(icon: .food, compact: false, selected: true)
        let compact = MapMarkerAppearance.image(icon: .food, compact: true, selected: false)
        XCTAssertTrue(normal === MapMarkerAppearance.image(icon: .food, compact: false, selected: false))
        XCTAssertEqual(normal.size.width, 44)
        XCTAssertNotEqual(normal.pngData(), selected.pngData())
        XCTAssertNotEqual(normal.pngData(), compact.pngData())
    }
}
