import XCTest
@testable import MapAnNai

private actor PagedServicesMock: MapServices {
    private(set) var calls: [(String, Int, SearchBounds?)] = []
    private(set) var cancellations = 0
    var failSecond = false
    func failNextSecondPage() { failSecond = true }
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] { [] }
    func details(at coordinate: Coordinate) async throws -> Place { throw AppError.message("unused") }
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TransportMode?) async throws -> PlannedRoute { throw AppError.message("unused") }
    func searchPage(_ query: String, bounds: SearchBounds?, request: PlaceSearchRequest) async throws -> PlaceSearchPage {
        calls.append((query, request.page, bounds))
        do { try await Task.sleep(for: .milliseconds(query == "slow" ? 2000 : 30)) }
        catch { cancellations += 1; throw error }
        if request.page == 2 && failSecond { failSecond = false; throw AppError.message("mock unavailable") }
        // page two repeats one POI intentionally: accumulated list must deduplicate.
        let ids = request.page == 1 ? Array(0..<20) : request.page == 2 ? Array(19..<39) : Array(39..<45)
        let places = ids.map { Place(id: "\(query)-\($0)", name: "\(query) \($0)", address: "地址", coordinates: Coordinate(latitude: 31, longitude: 121)) }
        return PlaceSearchPage(places: places, page: request.page, pageSize: 20, nextPage: request.page < 3 ? request.page + 1 : nil)
    }
}
final class SearchPaginationTests: XCTestCase {
    func testSavedTitlesMergeGloballyAndCoordinateMatchesReuseMarker() {
        let coordinate = Coordinate(latitude: 40.1234561, longitude: 116.1234561)
        let marker = Marker(id: "saved", coordinates: coordinate,
                            content: MarkerContent(id: "saved", title: "My Coffee", address: "Saved address", markdownContent: ""))
        let poi = Place(id: "provider", name: "Provider name", address: "Other address",
                        coordinates: Coordinate(latitude: 40.1234562, longitude: 116.1234562))
        let other = Place(id: "saved", name: "Another Coffee", address: "",
                          coordinates: Coordinate(latitude: 31, longitude: 121))
        let results = PlaceSearchMerger.merge(query: "coffee", markers: [marker], places: [poi, other, other])
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results.first?.markerId, marker.id)
        XCTAssertEqual(results.first?.name, marker.title)
        XCTAssertEqual(results.first?.address, "Saved address")
        XCTAssertNil(results.last?.markerId)
        XCTAssertEqual(PlaceSearchMerger.merge(query: "provider", markers: [marker], places: [poi]).first?.markerId, marker.id)
    }
    @MainActor func testPagesAppendDeduplicateFreezeBoundsAndDoNotMoveCamera() async {
        let services = PagedServicesMock()
        let actual = AppStore(settings: Settings(), demo: true, services: services)
        actual.bounds = SearchBounds(west: 121, south: 31, east: 122, north: 32)
        actual.searchText = "咖啡"; await actual.search()
        XCTAssertEqual(actual.searchResults.count, 20); XCTAssertTrue(actual.searchHasMore)
        let camera = actual.camera?.id
        actual.bounds = SearchBounds(west: 100, south: 20, east: 101, north: 21)
        async let one: Void = actual.loadMoreSearch()
        async let two: Void = actual.loadMoreSearch()
        _ = await (one, two)
        XCTAssertEqual(actual.searchResults.count, 39)
        XCTAssertEqual(actual.camera?.id, camera)
        await actual.loadMoreSearch()
        XCTAssertEqual(actual.searchResults.count, 45); XCTAssertFalse(actual.searchHasMore)
        await actual.loadMoreSearch()
        let calls = await services.calls
        XCTAssertEqual(calls.map { $0.1 }, [1, 2, 3])
        XCTAssertTrue(calls.allSatisfy { $0.2 == SearchBounds(west: 119, south: 29, east: 124, north: 34) })
    }
    @MainActor func testFailedPagePreservesResultsAndRetriesSamePage() async {
        let services = PagedServicesMock()
        let store = AppStore(settings: Settings(), demo: true, services: services)
        store.searchText = "咖啡"; await store.search()
        await services.failNextSecondPage(); await store.loadMoreSearch()
        XCTAssertEqual(store.searchResults.count, 20); XCTAssertNotNil(store.searchPageError)
        XCTAssertTrue(store.searchHasMore); XCTAssertFalse(store.loadingMoreSearch)
        await store.loadMoreSearch()
        XCTAssertEqual(store.searchResults.count, 39); XCTAssertNil(store.searchPageError)
        let calls = await services.calls
        XCTAssertEqual(calls.map { $0.1 }, [1, 2, 2])
    }
    @MainActor func testChangingQueryCancelsInFlightAndDiscardsOldResults() async throws {
        let services = PagedServicesMock()
        let store = AppStore(settings: Settings(), demo: true, services: services)
        store.searchText = "slow"
        let previous = Task { await store.search() }
        try await Task.sleep(for: .milliseconds(80))
        store.searchText = "new"; await store.search(); await previous.value
        XCTAssertEqual(store.searchResults.count, 20)
        XCTAssertTrue(store.searchResults.allSatisfy { $0.id.hasPrefix("new-") })
        let cancelled = await services.cancellations
        XCTAssertEqual(cancelled, 1)
        let next = Task { await store.loadMoreSearch() }
        store.clearSearch(); await next.value
        XCTAssertTrue(store.searchResults.isEmpty); XCTAssertFalse(store.searchHasMore)
    }
    func testServerPageMetadataAndLegacyFallback() async throws {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config); defer { session.invalidateAndCancel() }
        let services = ServerMapServices(client: APIClient(baseURL: "https://pages.invalid", token: "", session: session), configuration: .current)
        MockURLProtocol.handler = { request in
            let parts = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!
            XCTAssertEqual(parts.queryItems?.first { $0.name == "page" }?.value, "2")
            XCTAssertEqual(parts.queryItems?.first { $0.name == "pageToken" }?.value, "mock-token")
            return (200, Data(#"{"success":true,"data":[{"name":"咖啡","placeId":"","coordinates":{"latitude":31,"longitude":121}}],"page":2,"pageSize":20,"hasMore":true,"nextPage":3,"nextPageToken":"mock-last"}"#.utf8))
        }
        let result = try await services.searchPage("咖啡", bounds: nil, request: PlaceSearchRequest(page: 2, pageToken: "mock-token"))
        XCTAssertEqual(result.nextPage, 3); XCTAssertEqual(result.nextPageToken, "mock-last")
        XCTAssertFalse(result.places[0].id.isEmpty)
        MockURLProtocol.handler = { _ in (200, Data(#"{"success":true,"data":[]}"#.utf8)) }
        let legacy = try await services.searchPage("咖啡", bounds: nil, request: PlaceSearchRequest())
        XCTAssertNil(legacy.nextPage); XCTAssertTrue(legacy.places.isEmpty)
    }
}
