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
            return (200, Data("{}".utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.addSearchPlaceInBackground(place, edited: value, using: client()))
        store.draft = nil // The navigation destination closes immediately.
        store.select(trip: trip, day: trip.days[1], focus: false)
        XCTAssertTrue(store.saving)
        try await settle(store)
        XCTAssertEqual(membershipPath, "/api/trips/\(trip.id)/days/\(target.id)/markers")
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
            return (200, Data("{}".utf8))
        }
        defer { DelayedSaveProtocol.handler = nil }
        XCTAssertTrue(store.addSearchPlaceInBackground(place, edited: value, using: client()))
        store.endAddingPlace()
        store.select(trip: trip, day: trip.days[1], focus: false)
        try await settle(store)
        XCTAssertEqual(membershipPath, "/api/trips/\(trip.id)/days/\(target.id)/markers")
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

    @MainActor func testTripFailureRollsBackDatesAndRetainsEditorValues() async throws {
        let store = store()
        let sample = AppStore(settings: store.settings, demo: true)
        let trip = try XCTUnwrap(sample.trips.first)
        store.trips = [trip]
        let value = TripSaveDraft(trip: trip, name: "新旅行名", start: .fromDay("2026-10-05"), end: .fromDay(trip.endDate), emoji: "🚆")
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
        XCTAssertFalse(store.saveDayInBackground(day, using: client())) // Writes stay serial.
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
}
