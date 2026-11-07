import XCTest
@testable import MapAnNai

private final class NoteProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class TripMarkerNoteTests: XCTestCase {
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [NoteProtocol.self]
        return APIClient(baseURL: "https://notes.invalid", token: "mock", session: URLSession(configuration: config))
    }
    private func trip(_ id: String, member: Bool = false, note: Bool = false) -> Trip {
        Trip(id: id, name: id, startDate: "2026-11-08", endDate: "2026-11-09", days: [
            TripDay(id: id + "-day", tripId: id, date: "2026-11-08", markerIds: member ? ["m"] : [], chains: member ? [["m", "b", "m"]] : []),
            TripDay(id: id + "-empty", tripId: id, date: "2026-11-09", markerIds: [], chains: [])],
            markerNotes: note ? [TripMarkerNote(tripId: id, markerId: "m", title: id, content: "<p>" + id + "</p>", updatedAt: "raw-version")] : nil)
    }
    func testOldTripAndSnapshotRoundTrip() throws {
        let data = Data(#"{"id":"old","name":"old","startDate":"2026-11-08","endDate":"2026-11-08","days":[]}"#.utf8)
        XCTAssertTrue(try JSONDecoder().decode(Trip.self, from: data).notes.isEmpty)
        let value = trip("ff14", note: true)
        XCTAssertEqual(try JSONDecoder().decode(Trip.self, from: JSONEncoder().encode(value)), value)
        XCTAssertEqual(value.note(for: "m")?.updatedAt, "raw-version")
    }
    func testReferencesAndDeletionProtectionMatchServerScope() {
        let first = trip("ff14", member: true, note: true)
        let second = trip("ba", note: true)
        XCTAssertTrue(second.referencedMarkerIDs.contains("m"))
        XCTAssertFalse(Trip.exclusiveMarkerIDs(trips: [first, second], tripID: first.id, dayID: nil).contains("m"))
        XCTAssertFalse(Trip.exclusiveMarkerIDs(trips: [first], tripID: first.id, dayID: first.days[0].id).contains("m"))
        XCTAssertTrue(Trip.exclusiveMarkerIDs(trips: [second], tripID: second.id, dayID: nil).contains("m"))
        XCTAssertTrue(Trip.exclusiveMarkerIDs(trips: [trip("a", member: true)], tripID: "a", dayID: "a-day").contains("m"))
        XCTAssertEqual(first.days[0].removing("m").chains, [["b"]])
        XCTAssertEqual(first.notes.count, 1)
    }
    @MainActor func testTwoTripsShareIdentityButNotTitlesOrBody() throws {
        let marker = try XCTUnwrap(AppStore(settings: Settings(), demo: true).markers.first)
        var a = trip("ff14", note: true), b = trip("ba", note: true)
        a.markerNotes?[0] = TripMarkerNote(tripId: a.id, markerId: marker.id, title: "FF14", content: "ff14", updatedAt: "v")
        b.markerNotes?[0] = TripMarkerNote(tripId: b.id, markerId: marker.id, title: "BA", content: "ba", updatedAt: "v2")
        XCTAssertEqual(a.displayTitle(for: marker), "FF14 · " + marker.title)
        XCTAssertEqual(b.displayTitle(for: marker), "BA · " + marker.title)
        XCTAssertEqual(a.note(for: marker.id)?.content, "ff14")
        XCTAssertEqual(b.note(for: marker.id)?.content, "ba")
        XCTAssertEqual(marker.title, marker.content.title)
    }
    func testPatchAndCopySendStrictVersionedBodies() async throws {
        let client = client()
        var bodies: [[String: Any]] = []
        NoteProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer mock")
            XCTAssertEqual(request.url?.path, "/api/trips/t/markers/m/note")
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&bytes, maxLength: bytes.count); if n <= 0 { break }; data.append(contentsOf: bytes.prefix(n)) }
            }
            bodies.append(try JSONSerialization.jsonObject(with: data) as! [String: Any])
            return (200, Data(#"{"note":null}"#.utf8))
        }
        defer { NoteProtocol.handler = nil }
        _ = try await client.tripMarkerNote(tripID: "t", markerID: "m", method: "PATCH", title: "", content: "", expectedUpdatedAt: nil)
        _ = try await client.tripMarkerNote(tripID: "t", markerID: "m", method: "POST", expectedUpdatedAt: "2026-01-02T03:04:05.678Z")
        XCTAssertEqual(Set(bodies[0].keys), ["title", "content", "expectedUpdatedAt"])
        XCTAssertTrue(bodies[0]["expectedUpdatedAt"] is NSNull)
        XCTAssertEqual(Set(bodies[1].keys), ["expectedUpdatedAt"])
        XCTAssertEqual(bodies[1]["expectedUpdatedAt"] as? String, "2026-01-02T03:04:05.678Z")
    }
    func testConflictAndLegacy404NeverRetry() async {
        for status in [409, 404] {
            var requests = 0
            NoteProtocol.handler = { _ in requests += 1; return (status, Data(#"{"error":"failure"}"#.utf8)) }
            do {
                _ = try await client().tripMarkerNote(tripID: "t", markerID: "m", method: "PATCH", title: "draft", content: "<p>draft</p>")
                XCTFail("Must reject")
            } catch { XCTAssertTrue(error.localizedDescription.contains("草稿已保留")) }
            XCTAssertEqual(requests, 1)
        }
        NoteProtocol.handler = nil
    }
}
