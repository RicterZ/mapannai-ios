import XCTest
@testable import MapAnNai

/// Delays the response without blocking either the UI actor or URL loading thread.
private final class DelayedSaveProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    private var responseTask: Task<Void, Never>?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let handler = Self.handler
        responseTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
                guard let handler else { return }
                let (status, data) = try handler(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch { client?.urlProtocol(self, didFailWithError: error) }
        }
    }
    override func stopLoading() { responseTask?.cancel() }
}

final class BackgroundSaveTests: XCTestCase {
    @MainActor private func store() -> AppStore {
        let defaults = UserDefaults.standard
        let previousURL = defaults.object(forKey: "baseURL")
        defaults.set("", forKey: "baseURL")
        let settings = Settings()
        if let previousURL { defaults.set(previousURL, forKey: "baseURL") }
        else { defaults.removeObject(forKey: "baseURL") }
        return AppStore(settings: settings, demo: false)
    }
    private func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DelayedSaveProtocol.self]
        return APIClient(baseURL: "https://example.invalid", token: "", session: URLSession(configuration: config))
    }
    @MainActor private func settle(_ store: AppStore) async throws {
        for _ in 0..<100 where store.saving { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(store.saving)
    }
    @MainActor func testDayCreationIsImmediateAndFailureRestoresTripAndDraft() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        let original = store.trips[0]
        store.beginDayEditor(trip: original)
        var draft = try XCTUnwrap(store.dayEditorDraft)
        draft.title = "New day"; draft.markerIDs = [original.days[0].markerIds[0]]
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["title"] as? String, "New day")
            XCTAssertEqual(body["markerIds"] as? [String], draft.markerIDs)
            return (500, Data(#"{"error":"failed"}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.submitDayEditor(draft, using: client()))
        XCTAssertNil(store.dayEditorDraft)
        XCTAssertTrue(store.saving)
        XCTAssertEqual(store.trips[0].days.count, original.days.count + 1)
        XCTAssertEqual(store.trips[0].days.last?.title, "New day")
        XCTAssertFalse(store.submitDayEditor(draft, using: client()))
        try await settle(store)
        XCTAssertEqual(store.trips[0], original)
        store.resumeFailedSave()
        XCTAssertEqual(store.dayEditorDraft?.markerIDs, draft.markerIDs)
        XCTAssertEqual(store.dayEditorDraft?.title, draft.title)
    }

    @MainActor func testPartialDayCreationRetryReusesIDAndAllowsEmptyTitle() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        store.beginDayEditor(trip: store.trips[0])
        let draft = try XCTUnwrap(store.dayEditorDraft)
        let created = TripDay(id: "server-day", tripId: draft.tripID, date: draft.date, markerIds: [], chains: [])
        var posts = 0
        DelayedSaveProtocol.handler = { request in
            if request.httpMethod == "POST" {
                posts += 1
                return (200, try JSONEncoder().encode(created))
            }
            return (500, Data(#"{"error":"end date failed"}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.submitDayEditor(draft, using: client()))
        try await settle(store)
        XCTAssertTrue(store.trips[0].days.contains { $0.id == created.id })
        store.resumeFailedSave()
        let recovered = try XCTUnwrap(store.dayEditorDraft)
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            if request.url?.path.hasSuffix("/days/server-day") == true { return (200, try JSONEncoder().encode(created)) }
            return (200, Data("{}".utf8))
        }
        XCTAssertTrue(store.submitDayEditor(recovered, using: client()))
        try await settle(store)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(store.trips[0].days.filter { $0.id == created.id }.count, 1)
        XCTAssertEqual(store.trips[0].endDate, draft.date)
    }

    @MainActor func testDayEditorClearsThemeWithoutDroppingRoutes() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        let original = store.trips[0].days[0]
        store.beginDayEditor(trip: store.trips[0], day: original)
        var draft = try XCTUnwrap(store.dayEditorDraft)
        draft.title = "  "
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(body["title"] as? String, "")
            XCTAssertNil(body["chains"])
            var confirmed = original; confirmed.title = nil
            return (200, try JSONEncoder().encode(confirmed))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.submitDayEditor(draft, using: client()))
        XCTAssertEqual(store.trips[0].days.first { $0.id == original.id }?.title, "")
        try await settle(store)
        XCTAssertEqual(store.trips[0].days.first { $0.id == original.id }?.chains, original.chains)
        XCTAssertNil(store.trips[0].days.first { $0.id == original.id }?.title)
    }

    @MainActor func testTitleEditAllowsExistingUnloadedMarkerReferences() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        store.markers = []
        let original = store.trips[0].days[0]
        store.beginDayEditor(trip: store.trips[0], day: original)
        var draft = try XCTUnwrap(store.dayEditorDraft); draft.title = "New theme"
        DelayedSaveProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            XCTAssertEqual(Set(body.keys), ["title"])
            var saved = original; saved.title = "New theme"
            return (200, try JSONEncoder().encode(saved))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.submitDayEditor(draft, using: client()))
        try await settle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.trips[0].days.first { $0.id == original.id }?.markerIds, original.markerIds)
    }

    @MainActor func testOldDayCreationCannotPublishAfterConnectionChange() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        store.beginDayEditor(trip: store.trips[0])
        let draft = try XCTUnwrap(store.dayEditorDraft)
        DelayedSaveProtocol.handler = { _ in (500, Data(#"{"error":"old server"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.submitDayEditor(draft, using: client()))
        try await Task.sleep(for: .milliseconds(30))
        await store.connect()
        try await Task.sleep(for: .milliseconds(400))
        XCTAssertNil(store.dayEditorDraft)
        XCTAssertFalse(store.canResumeFailedSave)
        XCTAssertFalse(store.saving)
        XCTAssertNil(store.errorMessage)
    }

    @MainActor func testDayEditorRejectsExternalPlacesAndChangedDay() {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        store.beginDayEditor(trip: store.trips[0], day: store.trips[0].days[0])
        var draft = store.dayEditorDraft!
        draft.markerIDs.append("outside-trip")
        XCTAssertFalse(store.submitDayEditor(draft, using: client()))
        draft.markerIDs.removeLast()
        store.trips[0].days[0].title = "Changed elsewhere"
        XCTAssertFalse(store.submitDayEditor(draft, using: client()))
        XCTAssertFalse(store.saving)
    }

    @MainActor func testNewMarkerClosesDraftBeforeResponseAndOpensRealDetailAfterSave() async throws {
        let store = store()
        var draft = MarkerDraft(coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        draft.title = "保存的新地点"; store.draft = draft
        DelayedSaveProtocol.handler = { _ in
            (200, Data(#"{"id":"saved","coordinates":{"latitude":31.2,"longitude":121.4},"content":{"id":"saved","title":"保存的新地点","markdownContent":""}}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveMarkerInBackground(draft, using: client()))
        XCTAssertNil(store.draft)
        XCTAssertTrue(store.saving)
        XCTAssertNil(store.selectedMarker, "No fabricated marker ID while the server is pending")
        XCTAssertFalse(store.saveMarkerInBackground(draft, using: client()), "Duplicate submission is reserved synchronously")
        try await settle(store)
        XCTAssertEqual(store.selectedMarker?.id, "saved")
        XCTAssertEqual(store.markers.first?.title, draft.title)
    }
    @MainActor func testMarkerFailureRestoresOriginalAndRetainsAllDraftFields() async throws {
        let store = store()
        let original = Marker(id: "existing", coordinates: Coordinate(latitude: 31.2, longitude: 121.4),
            content: MarkerContent(id: "existing", title: "原名称", markdownContent: "原笔记"))
        store.markers = [original]; store.focus(original)
        var draft = MarkerDraft(marker: original)
        draft.title = "新名称"; draft.html = "<p>新笔记</p>"; draft.headerImage = "https://example.invalid/image.jpg"
        DelayedSaveProtocol.handler = { _ in (500, Data(#"{"error":"保存失败"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveMarkerInBackground(draft, using: client()))
        XCTAssertTrue(store.saving)
        XCTAssertEqual(store.markers[0].title, draft.title)
        try await settle(store)
        XCTAssertEqual(store.markers, [original])
        XCTAssertTrue(store.canResumeFailedSave)
        store.resumeFailedSave()
        XCTAssertEqual(store.draft?.title, draft.title)
        XCTAssertEqual(store.draft?.html, draft.html)
        XCTAssertEqual(store.draft?.headerImage, draft.headerImage)
    }
    @MainActor func testPartialMarkerSaveRetriesCreatedIDWithoutDuplicatePOST() async throws {
        let store = store()
        var draft = MarkerDraft(coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        draft.title = "地点"; draft.headerImage = "https://example.invalid/cover.jpg"
        var posts = 0
        DelayedSaveProtocol.handler = { request in
            if request.httpMethod == "POST" {
                posts += 1
                return (200, Data(#"{"id":"created","coordinates":{"latitude":31.2,"longitude":121.4},"content":{"id":"created","title":"地点","markdownContent":""}}"#.utf8))
            }
            return (500, Data(#"{"error":"更新封面失败"}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveMarkerInBackground(draft, using: client()))
        try await settle(store)
        XCTAssertEqual(posts, 1)
        XCTAssertTrue(store.canResumeFailedSave)
        store.resumeFailedSave()
        let recovered = try XCTUnwrap(store.draft)
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url?.path, "/api/markers/created")
            return (200, Data("{}".utf8))
        }
        XCTAssertTrue(store.saveMarkerInBackground(recovered, using: client()))
        try await settle(store)
        XCTAssertEqual(posts, 1)
        XCTAssertEqual(store.selectedMarker?.id, "created")
        XCTAssertEqual(store.selectedMarker?.content.headerImage, draft.headerImage)
    }
    @MainActor func testSearchSaveKeepsOriginalDayAfterEditorCloses() async throws {
        let store = store()
        let sample = AppStore(settings: store.settings, demo: true)
        store.trips = sample.trips
        let trip = try XCTUnwrap(store.trips.first)
        let target = trip.days[0]
        store.beginAddingPlace(to: target)
        let place = Place(id: "poi", name: "搜索地点", address: "地址", coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        let value = MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
        store.draft = value
        var membershipPath: String?
        DelayedSaveProtocol.handler = { request in
            if request.url?.path == "/api/markers" {
                return (200, Data(#"{"id":"search-saved","coordinates":{"latitude":31.2,"longitude":121.4},"content":{"id":"search-saved","title":"搜索地点","markdownContent":""}}"#.utf8))
            }
            membershipPath = request.url?.path
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            var confirmed = target
            confirmed.markerIds = body["markerIds"] as! [String]
            confirmed.chains = body["chains"] as! [[String]]
            return (200, try JSONEncoder().encode(confirmed))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.addSearchPlaceInBackground(place, edited: value, using: client()))
        store.draft = nil // The navigation destination closes immediately.
        store.select(trip: trip, day: trip.days[1], focus: false)
        XCTAssertTrue(store.saving)
        try await settle(store)
        XCTAssertEqual(membershipPath, "/api/trips/\(trip.id)/days/\(target.id)")
        XCTAssertTrue(store.trips[0].days[0].markerIds.contains("search-saved"))
        XCTAssertFalse(store.trips[0].days[1].markerIds.contains("search-saved"))
    }

    @MainActor func testJoinExistingMarkerUpdatesDayImmediatelyAndRollsBackFailure() async throws {
        let store = store()
        let sample = AppStore(settings: store.settings, demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        let day = store.trips[0].days[0], marker = store.markers[3]
        DelayedSaveProtocol.handler = { _ in (500, Data(#"{"error":"加入失败"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.addMarkerInBackground(marker, to: day, using: client()))
        XCTAssertTrue(store.trips[0].days[0].markerIds.contains(marker.id))
        XCTAssertTrue(store.saving)
        try await settle(store)
        XCTAssertEqual(store.trips[0].days[0], day)
        XCTAssertNotNil(store.errorMessage)
    }
    @MainActor func testSearchSaveFinishesFrozenDayEvenIfSearchClosesImmediately() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        let trip = store.trips[0], target = trip.days[0]
        store.beginAddingPlace(to: target)
        let place = Place(id: "poi", name: "地点", address: "", coordinates: Coordinate(latitude: 31.2, longitude: 121.4))
        let value = MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
        var membershipPath: String?
        DelayedSaveProtocol.handler = { request in
            if request.url?.path == "/api/markers" {
                return (200, Data(#"{"id":"saved-after-close","coordinates":{"latitude":31.2,"longitude":121.4},"content":{"id":"saved-after-close","title":"地点","markdownContent":""}}"#.utf8))
            }
            membershipPath = request.url?.path
            XCTAssertEqual(request.httpMethod, "PUT")
            let body = try JSONSerialization.jsonObject(with: requestBody(request)) as! [String: Any]
            var confirmed = target
            confirmed.markerIds = body["markerIds"] as! [String]
            confirmed.chains = body["chains"] as! [[String]]
            return (200, try JSONEncoder().encode(confirmed))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.addSearchPlaceInBackground(place, edited: value, using: client()))
        store.endAddingPlace()
        store.select(trip: trip, day: trip.days[1], focus: false)
        try await settle(store)
        XCTAssertEqual(membershipPath, "/api/trips/\(trip.id)/days/\(target.id)")
        XCTAssertTrue(store.trips[0].days[0].markerIds.contains("saved-after-close"))
        XCTAssertFalse(store.trips[0].days[1].markerIds.contains("saved-after-close"))
        XCTAssertNil(store.selectedMarker)
        XCTAssertFalse(store.placeSearchPresented)
    }
    @MainActor func testOldConnectionCompletionDoesNotClearNewSaveOrPublishOldResult() async throws {
        let store = store()
        var old = MarkerDraft(coordinates: Coordinate(latitude: 31.2, longitude: 121.4)); old.title = "旧服务"
        var new = MarkerDraft(coordinates: Coordinate(latitude: 32.2, longitude: 122.4)); new.title = "新服务"
        DelayedSaveProtocol.handler = { request in
            if request.url?.host == "old.invalid" { return (500, Data(#"{"error":"旧服务失败"}"#.utf8)) }
            return (200, Data(#"{"id":"new-server","coordinates":{"latitude":32.2,"longitude":122.4},"content":{"id":"new-server","title":"新服务","markdownContent":""}}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        let oldClient = APIClient(baseURL: "https://old.invalid", token: "", session: client().session)
        XCTAssertTrue(store.saveMarkerInBackground(old, using: oldClient))
        try await Task.sleep(for: .milliseconds(30))
        await store.connect() // Empty configuration resets the connection without real network traffic.
        XCTAssertTrue(store.saveMarkerInBackground(new, using: client()))
        try await settle(store)
        XCTAssertEqual(store.markers.map(\.id), ["new-server"])
        XCTAssertEqual(store.selectedMarker?.id, "new-server")
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.canResumeFailedSave)
    }

    @MainActor func testCreationFailureRetainsRangeAndIconForFullPageRecovery() async throws {
        let store = store()
        let value = TripSaveDraft(trip: nil, name: "京都秋日漫游", start: .fromDay("2026-10-23"),
                                  end: .fromDay("2026-10-26"), emoji: "🚆", destinations: [TripDestination(name: "京都市", latitude: 35.0116, longitude: 135.7681), TripDestination(name: "东京都", latitude: 35.6762, longitude: 139.6503)])
        DelayedSaveProtocol.handler = { request in
            let body = try JSONSerialization.jsonObject(with: request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&bytes, maxLength: bytes.count)
                return Data(bytes.prefix(max(0, count)))
            } ?? Data()) as? [String: Any]
            let destinations = body?["destinations"] as? [[String: Any]]
            XCTAssertEqual(destinations?.count, 2)
            let destination = destinations?.first
            XCTAssertEqual(destination?["name"] as? String, "京都市")
            XCTAssertEqual(destination?["latitude"] as? Double, 35.0116)
            return (500, Data(#"{"error":"保存失败"}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveTripInBackground(value, using: client()))
        XCTAssertTrue(store.saving)
        XCTAssertFalse(store.saveTripInBackground(value, using: client()))
        try await settle(store)
        store.resumeFailedSave()
        let restored = try XCTUnwrap(store.tripSaveRecovery)
        XCTAssertNil(restored.trip)
        XCTAssertEqual(restored.id, value.id); XCTAssertEqual(restored.name, value.name)
        XCTAssertEqual(restored.emoji, value.emoji)
        XCTAssertEqual(restored.destinations, value.destinations)
        XCTAssertEqual(restored.start, value.start); XCTAssertEqual(restored.end, value.end)
    }
    @MainActor func testCreationRejectsMissingAndInvalidDestinationBeforeWrite() {
        let store = store()
        var draft = TripSaveDraft(trip: nil, name: "旅途", start: .fromDay("2026-10-23"), end: .fromDay("2026-10-26"), emoji: "✈️")
        XCTAssertFalse(store.saveTripInBackground(draft, using: client())); XCTAssertFalse(store.saving)
        draft.destinations = [TripDestination(name: "京都市", latitude: 91, longitude: 135)]
        XCTAssertFalse(store.saveTripInBackground(draft, using: client())); XCTAssertFalse(store.saving)
    }
    @MainActor func testCreationRejectsDuplicateAndOverLimitDestinations() {
        let store = store()
        let city = TripDestination(name: "京都市", latitude: 35, longitude: 135)
        var draft = TripSaveDraft(trip: nil, name: "旅途", start: .fromDay("2026-10-23"), end: .fromDay("2026-10-26"), emoji: "✈️", destinations: [city, city])
        XCTAssertFalse(store.saveTripInBackground(draft, using: client())); XCTAssertFalse(store.saving)
        draft.destinations = (0..<21).map { TripDestination(name: "城市\($0)", latitude: Double($0), longitude: 135) }
        XCTAssertFalse(store.saveTripInBackground(draft, using: client())); XCTAssertFalse(store.saving)
    }
    func testTripReadsLegacyDestinationAndPrefersNewOrderedList() throws {
        let legacy = Data(#"{"id":"trip","name":"旧旅行","startDate":"2026-10-01","endDate":"2026-10-02","days":[],"destination":{"name":"京都市","latitude":35,"longitude":135}}"#.utf8)
        var trip = try JSONDecoder().decode(Trip.self, from: legacy)
        XCTAssertEqual(trip.selectedDestinations.map(\.name), ["京都市"])
        trip.destinations = [TripDestination(name: "东京都", latitude: 35.6, longitude: 139.6)]
        XCTAssertEqual(trip.selectedDestinations.map(\.name), ["东京都"])
        trip.destinations = []
        XCTAssertTrue(trip.selectedDestinations.isEmpty)
    }

    func testDestinationSearchUsesExistingContractAndRejectsInvalidCoordinates() async throws {
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/destinations")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "东京 & 京都")
            return (200, Data(#"{"data":[{"name":"京都市","latitude":35.0116,"longitude":135.7681}]}"#.utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        let results = try await client().searchDestinations("东京 & 京都")
        XCTAssertEqual(results.first?.name, "京都市")
        DelayedSaveProtocol.handler = { _ in (200, Data(#"{"data":[{"name":"无效","latitude":95,"longitude":135}]}"#.utf8)) }
        do { _ = try await client().searchDestinations("东京"); XCTFail("Invalid coordinates must be rejected") } catch { }
    }

    @MainActor func testCreationRejectsInvalidRangeBeforeReservingAWrite() {
        let store = store()
        let reversed = TripSaveDraft(trip: nil, name: "旅途", start: .fromDay("2026-10-26"), end: .fromDay("2026-10-23"), emoji: "✈️", destinations: [TripDestination(name: "京都市", latitude: 35, longitude: 135)])
        XCTAssertFalse(store.saveTripInBackground(reversed, using: client())); XCTAssertFalse(store.saving)
        let tooLong = TripSaveDraft(trip: nil, name: "旅途", start: .fromDay("2026-01-01"), end: .fromDay("2027-01-03"), emoji: "✈️", destinations: [TripDestination(name: "京都市", latitude: 35, longitude: 135)])
        XCTAssertFalse(store.saveTripInBackground(tooLong, using: client())); XCTAssertFalse(store.saving)
    }
    @MainActor func testTripEditRejectsShorteningBeforeMutation() {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        let trip = store.trips[0]
        let draft = TripSaveDraft(trip: trip, name: trip.name, start: .fromDay("2026-11-01"), end: .fromDay("2026-11-01"), emoji: "✈️")
        XCTAssertFalse(store.saveTripInBackground(draft, using: client()))
        XCTAssertFalse(store.saving); XCTAssertEqual(store.trips[0], trip)
    }
    @MainActor func testTripExtensionRetainsOriginalIDsAndRetriesOnlyMissingDays() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        let trip = store.trips[0]
        var server = trip, posts: [String] = []
        var failFourth = true
        DelayedSaveProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200, try JSONEncoder().encode(server)) }
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                let count = stream.read(&buffer, maxLength: buffer.count)
                data = Data(buffer.prefix(max(0, count)))
            }
            let body = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertNil(body["destinations"], "Editing must retain destination metadata")
            if request.httpMethod == "POST" {
                let date = try XCTUnwrap(body["date"] as? String)
                if date == "2026-10-08", failFourth { return (500, Data(#"{"error":"添加失败"}"#.utf8)) }
                XCTAssertFalse(server.days.contains { $0.date == date })
                posts.append(date)
                let day = TripDay(id: "created-" + date, tripId: server.id, date: date, markerIds: [], chains: [])
                server.days.append(day)
                return (200, try JSONEncoder().encode(day))
            }
            if let start = body["startDate"] as? String, start != server.startDate {
                server.startDate = start
                for index in server.days.indices {
                    server.days[index].date = "2026-10-0\(5 + index)"
                }
                server.endDate = server.days.last!.date
            }
            if let end = body["endDate"] as? String { server.endDate = end }
            return (200, Data("{}".utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        let draft = TripSaveDraft(trip: trip, name: "延长旅途", start: .fromDay("2026-10-05"), end: .fromDay("2026-10-08"), emoji: "🚆")
        XCTAssertTrue(store.saveTripInBackground(draft, using: client()))
        XCTAssertEqual(store.trips[0].days.count, 4)
        XCTAssertEqual(Array(store.trips[0].days.prefix(2).map(\.id)), trip.days.map(\.id))
        XCTAssertEqual(store.trips[0].days[0].chains, trip.days[0].chains)
        try await settle(store)
        XCTAssertEqual(store.trips[0], trip)
        store.resumeFailedSave()
        failFourth = false
        XCTAssertTrue(store.saveTripInBackground(try XCTUnwrap(store.tripSaveRecovery), using: client()))
        try await settle(store)
        XCTAssertEqual(posts, ["2026-10-07", "2026-10-08"])
        XCTAssertEqual(server.days.count, 4)
        XCTAssertEqual(store.trips[0].days.map(\.id), server.days.map(\.id))
        XCTAssertEqual(server.endDate, "2026-10-08")
        XCTAssertEqual(server.days[0].chains, trip.days[0].chains)
        XCTAssertEqual(Array(server.days.prefix(2).map(\.id)), trip.days.map(\.id))
    }
    @MainActor func testTripFailureRollsBackDatesAndRetainsEditorValues() async throws {
        let store = store()
        let sample = AppStore(settings: store.settings, demo: true)
        let trip = try XCTUnwrap(sample.trips.first)
        store.trips = [trip]
        let value = TripSaveDraft(trip: trip, name: "新旅行名", start: .fromDay("2026-10-05"), end: .fromDay("2026-10-06"), emoji: "🚆")
        DelayedSaveProtocol.handler = { _ in (500, Data(#"{"error":"保存失败"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveTripInBackground(value, using: client()))
        XCTAssertTrue(store.saving)
        XCTAssertEqual(store.trips[0].name, value.name)
        XCTAssertEqual(store.trips[0].days[0].date, "2026-10-05")
        try await settle(store)
        XCTAssertEqual(store.trips, [trip])
        store.resumeFailedSave()
        XCTAssertEqual(store.tripSaveRecovery?.id, value.id)
        XCTAssertEqual(store.tripSaveRecovery?.name, value.name)
        XCTAssertEqual(store.tripSaveRecovery?.start, value.start)
        XCTAssertEqual(store.tripSaveRecovery?.emoji, value.emoji)
    }
}

extension BackgroundSaveTests {
    @MainActor func testQueuedDayEditsPublishImmediatelyAndWriteInOrder() async throws {
        let store = store()
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: ["a", "b", "c"], chains: [["a", "b", "c"]])
        store.trips = [Trip(id: "trip", name: "Test", startDate: day.date, endDate: day.date, days: [day])]
        let first = day.removing("a"), second = first.removing("b")
        var requests = 0
        DelayedSaveProtocol.handler = { _ in
            requests += 1
            return (200, try! JSONEncoder().encode(requests == 1 ? first : second))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveDayInBackground(first, using: client()))
        XCTAssertTrue(store.saveDayInBackground(second, using: client()))
        XCTAssertEqual(store.trips[0].days[0], second)
        XCTAssertTrue(store.canEditItinerary)
        XCTAssertEqual(requests, 0)
        try await settle(store)
        XCTAssertEqual(requests, 2)
        XCTAssertEqual(store.trips[0].days[0], second)
    }
    @MainActor func testFailedQueuedDayEditsRollbackInReverseAndCancelDependents() async throws {
        let store = store()
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: ["a", "b", "c"], chains: [["a", "b", "c"]])
        store.trips = [Trip(id: "trip", name: "Test", startDate: day.date, endDate: day.date, days: [day])]
        var requests = 0
        DelayedSaveProtocol.handler = { _ in requests += 1; return (500, Data(#"{"error":"Failed"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        let first = day.removing("a"), second = first.removing("b")
        XCTAssertTrue(store.saveDayInBackground(first, using: client()))
        XCTAssertTrue(store.saveDayInBackground(second, using: client()))
        try await settle(store)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(store.trips[0].days[0], day)
    }
}

extension BackgroundSaveTests {
    @MainActor func testRouteDropPublishesVisitsAndEdgesBeforeDelayedAPIReturns() async throws {
        let store = store()
        let route = RouteChain(id: "route", stops: [
            ChainStop(id: "a", markerId: "ma", startTime: "09:30"),
            ChainStop(id: "b", markerId: "mb", startTime: "10:00"),
            ChainStop(id: "c", markerId: "mc")],
            legs: [ChainLeg(fromStopId: "a", toStopId: "b", mode: .train, serviceNumber: "G123")])
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: ["ma", "mb", "mc"], chains: [["ma", "mb", "mc"]], routeChains: [route])
        store.trips = [Trip(id: "trip", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        var changed = day; changed.setRouteOrders([["ma", "mc", "mb"]])
        let response = try JSONEncoder().encode(changed)
        DelayedSaveProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "PATCH")
            XCTAssertEqual(request.url?.path, "/api/trips/trip/days/day/chains/route")
            return (200, response)
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveDayInBackground(changed, animated: false, using: client()))
        XCTAssertTrue(store.saving)
        XCTAssertEqual(store.trips[0].days[0], changed)
        XCTAssertEqual(store.trips[0].days[0].routeChains?[0].stops[2].startTime, "10:00")
        XCTAssertTrue(store.trips[0].days[0].routeChains?[0].legs.isEmpty == true)
        XCTAssertEqual(store.trips[0].days[0].routeChains?[0].inactiveLegs?.first?.serviceNumber, "G123")
        XCTAssertTrue(store.canEditItinerary) // Background writes no longer lock editing.
        try await settle(store)
        XCTAssertEqual(store.trips[0].days[0], changed)
    }
    @MainActor func testFailedRouteDropRestoresVisitsActiveAndInactiveEdges() async throws {
        let store = store()
        let route = RouteChain(id: "route", stops: [ChainStop(id: "a", markerId: "ma"), ChainStop(id: "b", markerId: "mb"), ChainStop(id: "c", markerId: "mc")], legs: [ChainLeg(fromStopId: "a", toStopId: "b", mode: .bus, serviceNumber: "101")])
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: ["ma", "mb", "mc"], chains: [["ma", "mb", "mc"]], routeChains: [route])
        store.trips = [Trip(id: "trip", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        var changed = day; changed.setRouteOrders([["mb", "ma", "mc"]])
        DelayedSaveProtocol.handler = { _ in (500, Data(#"{"error":"路线保存失败"}"#.utf8)) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveDayInBackground(changed, animated: false, using: client()))
        XCTAssertEqual(store.trips[0].days[0], changed)
        try await settle(store)
        XCTAssertEqual(store.trips[0].days[0], day)
        XCTAssertEqual(store.errorMessage, "路线保存失败")
    }
    @MainActor func testServerAssignedVisitIDsAreAdoptedWithoutWaitingForRefresh() async throws {
        let store = store()
        let route = RouteChain(id: "route", stops: [ChainStop(id: "a", markerId: "ma"), ChainStop(id: "b", markerId: "mb")], legs: [])
        let day = TripDay(id: "day", tripId: "trip", date: "2026-10-03", markerIds: ["ma", "mb", "mc"], chains: [["ma", "mb"]], routeChains: [route])
        store.trips = [Trip(id: "trip", name: "测试", startDate: day.date, endDate: day.date, days: [day])]
        var changed = day; changed.setRouteOrders([["ma", "mc", "mb"]])
        var confirmed = changed; confirmed.routeChains?[0].stops[1].id = "server-visit-c"
        let response = try JSONEncoder().encode(confirmed)
        DelayedSaveProtocol.handler = { _ in (200, response) }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.saveDayInBackground(changed, animated: false, using: client()))
        try await settle(store)
        XCTAssertEqual(store.trips[0].days[0].routeChains?[0].stops[1].id, "server-visit-c")
        XCTAssertEqual(store.trips[0].days[0].chains, changed.chains)
    }
    func testDefaultRoutePlacementAndDuplicateMembership() {
        let empty = TripDay(id: "day", tripId: "trip", date: "2026-10-12", markerIds: [], chains: [])
        let first = empty.addingToDefaultRoute(["a", "a"])
        XCTAssertEqual(first.markerIds, ["a"]); XCTAssertEqual(first.chains, [["a"]])
        let second = first.addingToDefaultRoute(["a", "b"])
        XCTAssertEqual(second.markerIds, ["a", "b"]); XCTAssertEqual(second.chains, [["a", "b"]])
        var multiple = second; multiple.markerIds.append("c"); multiple.chains.append(["c"])
        let isolated = multiple.addingToDefaultRoute(["d"])
        XCTAssertEqual(isolated.chains, multiple.chains)
        XCTAssertEqual(isolated.markerIds, ["a", "b", "c", "d"])
        XCTAssertEqual(isolated.addingToDefaultRoute(["d"]), isolated)
    }
    @MainActor func testCopyPlacesReusesIDsAndOnlyWritesDestination() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips; store.markers = sample.markers
        let source = store.trips[0].days[0], destination = store.trips[0].days[1]
        let expected = destination.addingToDefaultRoute(["demo-0", "demo-1"])
        var paths: [String] = []
        DelayedSaveProtocol.handler = { request in
            paths.append(request.url!.path)
            XCTAssertEqual(request.httpMethod, "PUT")
            XCTAssertEqual(request.url!.path, ("/api/" + AppStore.dayPath(destination)).removingPercentEncoding!)
            return (200, try JSONEncoder().encode(expected))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.transferDayPlaces(["demo-0", "demo-1"], from: source, to: destination, copy: true, using: client()))
        XCTAssertEqual(store.trips[0].days[0], source)
        XCTAssertEqual(store.trips[0].days[1].chains, expected.chains)
        XCTAssertFalse(store.transferDayPlaces(["demo-0"], from: source, to: destination, copy: true, using: client()))
        try await settle(store)
        XCTAssertEqual(paths.count, 1)
        XCTAssertEqual(store.trips[0].days[0], source)
        XCTAssertEqual(store.markers, sample.markers, "Copying membership never creates a place")
    }
    @MainActor func testFailedMoveRestoresBothDaysAndCompensatesDestination() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        let original = store.trips[0].days
        let source = original[0], destination = original[1]
        var requests: [String] = []
        DelayedSaveProtocol.handler = { request in
            requests.append(request.httpMethod! + " " + request.url!.path)
            if request.url!.path == ("/api/" + AppStore.dayPath(source)).removingPercentEncoding! {
                return request.httpMethod == "GET" ? (200, try JSONEncoder().encode(source)) : (500, Data("{}".utf8))
            }
            return (200, try JSONEncoder().encode(requests.count == 1 ? destination.addingToDefaultRoute(["demo-0"]) : destination))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.transferDayPlaces(["demo-0"], from: source, to: destination, copy: false, using: client()))
        XCTAssertFalse(store.trips[0].days[0].markerIds.contains("demo-0"))
        XCTAssertTrue(store.trips[0].days[1].markerIds.contains("demo-0"))
        try await settle(store)
        XCTAssertEqual(store.trips[0].days, original)
        XCTAssertEqual(requests, [("PUT /api/" + AppStore.dayPath(destination)).removingPercentEncoding!, ("PUT /api/" + AppStore.dayPath(source)).removingPercentEncoding!,
                                  ("GET /api/" + AppStore.dayPath(source)).removingPercentEncoding!, ("PUT /api/" + AppStore.dayPath(destination)).removingPercentEncoding!])
        XCTAssertNotNil(store.errorMessage)
    }
    @MainActor func testLostMoveResponseDoesNotUndoSuccessfullyMovedPlace() async throws {
        let store = store(), sample = AppStore(settings: Settings(), demo: true)
        store.trips = sample.trips
        let source = store.trips[0].days[0], destination = store.trips[0].days[1]
        let movedSource = source.removing("demo-0"), movedDestination = destination.addingToDefaultRoute(["demo-0"])
        var destinationWrites = 0
        DelayedSaveProtocol.handler = { request in
            if request.url!.path == ("/api/" + AppStore.dayPath(destination)).removingPercentEncoding! {
                destinationWrites += 1
                return (200, try JSONEncoder().encode(movedDestination))
            }
            return request.httpMethod == "GET" ? (200, try JSONEncoder().encode(movedSource)) : (500, Data("{}".utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.transferDayPlaces(["demo-0"], from: source, to: destination, copy: false, using: client()))
        try await settle(store)
        XCTAssertEqual(destinationWrites, 1)
        XCTAssertEqual(store.trips[0].days[0], movedSource)
        XCTAssertEqual(store.trips[0].days[1], movedDestination)
    }

}
