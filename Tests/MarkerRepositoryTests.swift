import XCTest
@testable import MapAnNai

final class MarkerRepositoryTests: XCTestCase {
    private var directory: URL!
    private var repository: MarkerRepository!
    private var client: APIClient!
    override func setUp() {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        repository = MarkerRepository(directory: directory)
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [MockURLProtocol.self]
        client = APIClient(baseURL: "https://cache-test.invalid", token: "test-account", session: URLSession(configuration: config))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: directory) }
    private func marker(_ title: String = "缓存地点", address: String? = "保留地址") -> Marker {
        Marker(id: "m", coordinates: Coordinate(latitude: 31, longitude: 121),
               content: MarkerContent(id: "m", title: title, address: address, markdownContent: "笔记"))
    }
    private func seed(_ markers: [Marker], date: Date = .distantPast) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = MarkerSnapshot(markers: markers, trips: [], fetchedAt: date)
        try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent(MarkerRepository.scope(client) + ".json"))
    }
    func testDiskCacheSurvivesRepositoryAndIsolatesAccountAndServer() async throws {
        try seed([marker()])
        let cached = await repository.cached(using: client)
        XCTAssertEqual(cached?.markers.first?.title, "缓存地点")
        var other = APIClient(baseURL: client.baseURL, token: "another-account", session: client.session)
        let otherAccount = await repository.cached(using: other)
        XCTAssertNil(otherAccount)
        other = APIClient(baseURL: "https://another.invalid", token: client.token, session: client.session)
        let otherServer = await repository.cached(using: other)
        XCTAssertNil(otherServer)
        let reopened = MarkerRepository(directory: directory)
        let restored = await reopened.cached(using: client)
        XCTAssertEqual(restored?.markers, cached?.markers)
    }
    func testFreshListAvoidsBothListAndDetailRequests() async throws {
        try seed([marker()], date: Date())
        MockURLProtocol.handler = { _ in XCTFail("Fresh cache should not request"); return (500, Data()) }
        let snapshot = try await repository.refresh(using: client)
        XCTAssertEqual(snapshot.markers.first?.title, "缓存地点")
        let detail = try await repository.detail("m", using: client)
        XCTAssertNil(detail)
    }
    func testStaleDetailUpdatesAndPreservesAddressThenThrottles() async throws {
        try seed([marker()])
        let response = try JSONEncoder().encode(marker("更新的名称", address: nil))
        var count = 0
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/markers/m")
            count += 1; return (200, response)
        }
        let refreshed = try await repository.detail("m", using: client)
        XCTAssertEqual(refreshed?.title, "更新的名称")
        XCTAssertEqual(refreshed?.content.address, "保留地址")
        let repeated = try await repository.detail("m", using: client)
        XCTAssertNil(repeated); XCTAssertEqual(count, 1)
        let disk = MarkerRepository(directory: directory)
        let cached = await disk.cached(using: client)
        XCTAssertEqual(cached?.markers.first, refreshed)
    }
    func testBackgroundFailureRetainsCachedContentAndThrottlesRetries() async throws {
        try seed([marker()])
        var count = 0
        MockURLProtocol.handler = { _ in count += 1; return (500, Data(#"{"error":"失败"}"#.utf8)) }
        do { _ = try await repository.detail("m", using: client); XCTFail("Expected failure") } catch {}
        let repeated = try await repository.detail("m", using: client)
        XCTAssertNil(repeated); XCTAssertEqual(count, 1)
        let cached = await repository.cached(using: client)
        XCTAssertEqual(cached?.markers, [marker()])
    }
    func testFullRefreshIncludesDeletionAndInvalidationForcesReload() async throws {
        try seed([marker()], date: Date())
        var count = 0
        MockURLProtocol.handler = { _ in count += 1; return (200, Data("[]".utf8)) }
        await repository.invalidate(using: client)
        let result = try await repository.refresh(using: client)
        XCTAssertTrue(result.markers.isEmpty); XCTAssertEqual(count, 2)
        _ = try await repository.refresh(using: client)
        XCTAssertEqual(count, 2)
    }
    func testConcurrentRefreshesShareRequests() async throws {
        MockURLProtocol.handler = { _ in
            Thread.sleep(forTimeInterval: 0.05)
            return (200, Data("[]".utf8))
        }
        async let first = repository.refresh(using: client)
        async let second = repository.refresh(using: client)
        let values = try await (first, second)
        XCTAssertEqual(values.0.fetchedAt, values.1.fetchedAt)
    }
    func testInvalidationRejectsOldInFlightRefresh() async throws {
        try seed([marker()])
        let started = expectation(description: "Both list reads started")
        started.expectedFulfillmentCount = 2
        MockURLProtocol.handler = { _ in
            started.fulfill()
            Thread.sleep(forTimeInterval: 0.1)
            return (200, Data("[]".utf8))
        }
        let repository = repository!, client = client!
        let pending = Task { try await repository.refresh(using: client, force: true) }
        await fulfillment(of: [started], timeout: 2)
        await repository.invalidate(using: client)
        do { _ = try await pending.value; XCTFail("Old result must be rejected") } catch {}
        let cached = await repository.cached(using: client)
        XCTAssertEqual(cached?.markers, [marker()])
    }
    func testConcurrentDetailReadsShareOneRequest() async throws {
        try seed([marker()])
        let response = try JSONEncoder().encode(marker("新名称", address: nil))
        let lock = NSLock(); var requests = 0
        MockURLProtocol.handler = { _ in
            lock.lock(); requests += 1; lock.unlock()
            Thread.sleep(forTimeInterval: 0.05)
            return (200, response)
        }
        async let first = repository.detail("m", using: client)
        async let second = repository.detail("m", using: client)
        let values = try await (first, second)
        XCTAssertEqual([values.0, values.1].compactMap { $0 }.count, 1)
        XCTAssertEqual(requests, 1)
        XCTAssertEqual((values.0 ?? values.1)?.content.address, "保留地址")
    }

}
