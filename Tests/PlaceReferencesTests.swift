import XCTest
@testable import MapAnNai

final class PlaceReferencesTests: XCTestCase {
    private static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var result = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            result.append(buffer, count: count)
        }
        return result
    }
    func testLegacyAndMultiPlatformMarkerRoundTrip() throws {
        let legacy = Data(#"{"id":"test","coordinates":{"latitude":35,"longitude":139},"content":{"id":"test","markdownContent":""}}"#.utf8)
        var marker = try JSONDecoder().decode(Marker.self, from: legacy)
        XCTAssertNil(marker.placeReferences)
        marker.placeReferences = PlaceReferences(apple: PlaceReference(placeId: "opaque_apple"), google: PlaceReference(placeId: "opaque_google"), amap: PlaceReference(placeId: "opaque_amap"))
        let decoded = try JSONDecoder().decode(Marker.self, from: JSONEncoder().encode(marker))
        XCTAssertEqual(decoded.placeReferences, marker.placeReferences)
        XCTAssertEqual(MarkerDraft(marker: decoded).placeReferences, marker.placeReferences)
    }
    @MainActor func testSearchPreservesExplicitReferencesWithoutInferringInternalID() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://example.invalid", token: "", session: URLSession(configuration: config))
        defer { MockURLProtocol.handler = nil }
        MockURLProtocol.handler = { _ in
            (200, Data(#"{"success":true,"data":[{"id":"internal","placeId":"legacy-id","name":"Explicit","coordinates":{"latitude":35,"longitude":139},"placeReferences":{"google":{"placeId":"official"}}},{"id":"internal-2","placeId":"legacy-2","name":"Legacy","coordinates":{"latitude":36,"longitude":140}}]}"#.utf8))
        }
        let results = try await ServerMapServices(client: client, configuration: .current).search("test", bounds: nil)
        XCTAssertEqual(results[0].placeReferences?.google?.placeId, "official")
        XCTAssertNil(results[1].placeReferences)
    }
    @MainActor func testGoogleNavigationIncludesOfficialIdentity() throws {
        let marker = Marker(id: "test", coordinates: Coordinate(latitude: 35, longitude: 139), content: MarkerContent(id: "test", markdownContent: ""), placeReferences: PlaceReferences(google: PlaceReference(placeId: "opaque&+id")))
        let url = try XCTUnwrap(MarkerPresentation.googleNavigationURL(for: marker))
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(items.first { $0.name == "destination_place_id" }?.value, "opaque&+id")
        XCTAssertEqual(items.first { $0.name == "destination" }?.value, "35.0,139.0")
    }
    @MainActor func testCreateTransmitsReferencesAndUsesDeduplicatedResponse() async throws {
        let store = AppStore(settings: Settings(), demo: false)
        var draft = MarkerDraft(coordinates: Coordinate(latitude: 35, longitude: 139), title: "Test", placeReferences: PlaceReferences(google: PlaceReference(placeId: "official")))
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let client = APIClient(baseURL: "https://example.invalid", token: "", session: URLSession(configuration: config))
        defer { MockURLProtocol.handler = nil }
        MockURLProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            let refs = body["placeReferences"] as? [String: [String: String]]
            XCTAssertEqual(refs?["google"]?["placeId"], "official")
            return (200, Data(#"{"id":"existing","coordinates":{"latitude":35,"longitude":139},"content":{"id":"existing","markdownContent":""}}"#.utf8))
        }
        let saved = await store.saveMarker(draft, using: client)
        XCTAssertTrue(saved)
        XCTAssertNil(store.markers.first?.placeReferences)
        draft = MarkerDraft(marker: try XCTUnwrap(store.markers.first))
        draft.title = "Edited"
        MockURLProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            XCTAssertNil(body["placeReferences"])
            return (200, Data(#"{"success":true}"#.utf8))
        }
        let edited = await store.saveMarker(draft, using: client)
        XCTAssertTrue(edited)
    }
}
