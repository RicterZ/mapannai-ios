import XCTest
@testable import MapAnNai

private final class BackgroundRunProtocol: URLProtocol {
    static var payload = Data()
    static var status = 200
    static var inspect: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.inspect?(request)
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class AIBackgroundRunTests: XCTestCase {
    func testStartPollAndExplicitCancelUseRunCapabilityAndCursor() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [BackgroundRunProtocol.self]
        let service = AIPlannerService(client: APIClient(baseURL: "https://map.invalid", token: "map-test"), sessionConfiguration: config)
        var run = AIBackgroundRun(token: "capability-test", requestID: UUID())
        var request = AIRequest(settings: AIConfiguration(model: "test"), messages: [AIMessage(role: "user", content: "test")], context: AIContext(localDate: "2026-10-16", tripId: nil, dayId: nil))
        request.conversationId = UUID(); request.requestId = run.requestID
        BackgroundRunProtocol.status = 202
        let id = String(repeating: "a", count: 48)
        BackgroundRunProtocol.payload = Data("{\"id\":\"\(id)\"}".utf8)
        BackgroundRunProtocol.inspect = { req in
            XCTAssertEqual(req.httpMethod, "POST")
            XCTAssertEqual(req.url?.path, "/api/ai/runs")
            XCTAssertEqual(req.value(forHTTPHeaderField: "x-run-token"), "capability-test")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer map-test")
        }
        defer { BackgroundRunProtocol.inspect = nil }
        run.id = try await service.startRun(request, token: run.token)
        run.cursor = 7
        BackgroundRunProtocol.status = 200
        BackgroundRunProtocol.payload = Data(#"{"status":"completed","events":[{"seq":8,"event":{"type":"partial","text":"结果"}},{"seq":9,"event":{"type":"complete"}}],"cursor":9}"#.utf8)
        BackgroundRunProtocol.inspect = { req in
            XCTAssertEqual(req.httpMethod, "GET"); XCTAssertEqual(req.url?.query, "after=7")
        }
        let page = try await service.readRun(run)
        XCTAssertEqual(page.events.map(\.seq), [8,9]); XCTAssertEqual(page.cursor, 9)
        XCTAssertEqual(page.events.first?.event.text, "结果")
        BackgroundRunProtocol.inspect = { req in XCTAssertEqual(req.httpMethod, "DELETE") }
        try await service.cancelRun(run)
    }
    func testCheckpointHasCursorAndNoCapabilitiesInHistoryJSON() throws {
        let request = UUID()
        let token = "unit-test-capability"
        try Keychain.write(token, key: "ai-run-" + request.uuidString)
        defer { try? Keychain.write("", key: "ai-run-" + request.uuidString) }
        var run = AIBackgroundRun(token: token, requestID: request)
        run.id = String(repeating: "b", count: 48); run.cursor = 33; run.partial = "已收到"
        var conversation = AIConversation(); conversation.pendingRun = run
        let data = try JSONEncoder().encode(conversation)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains(token))
        let restored = try JSONDecoder().decode(AIConversation.self, from: data)
        XCTAssertEqual(restored.pendingRun?.cursor, 33)
        XCTAssertEqual(restored.pendingRun?.token, token)
        XCTAssertEqual(restored.pendingRun?.partial, "已收到")
    }
    @MainActor func testBackgroundExpiryDoesNotStopServerOrLosePendingRun() {
        let planner = AIPlannerStore()
        var conversation = AIConversation()
        conversation.pendingRun = AIBackgroundRun(token: "test", requestID: UUID())
        planner.conversations = [conversation]; planner.activeID = conversation.id
        planner.expireBackgroundExecution()
        XCTAssertNotNil(planner.conversation?.pendingRun)
        XCTAssertNil(planner.error)
    }
}
