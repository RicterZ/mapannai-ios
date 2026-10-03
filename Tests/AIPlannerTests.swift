import XCTest
@testable import MapAnNai

final class AIPlannerTests: XCTestCase {
    @MainActor func testStopPreservesPartialReplyWithoutRepeatingIt() {
        let planner = AIPlannerStore()
        let conversation = AIConversation()
        planner.conversations = [conversation]
        planner.activeID = conversation.id
        planner.partial = "已收到的回复"
        planner.stop()
        XCTAssertEqual(planner.conversation?.messages.last?.content, "已收到的回复")
        XCTAssertEqual(planner.partial, "")
        planner.stop()
        XCTAssertEqual(planner.conversation?.messages.count, 1)
    }

    func testRequestUsesServerContractWithoutSystemPromptOrTools() throws {
        let request = AIRequest(settings: AIConfiguration(baseUrl: "https://model.example/v1", apiKey: "test-key", model: "test-model"),
            messages: [AIMessage(role: "user", content: "安排东京三天"), AIMessage(role: "assistant", content: nil)],
            context: AIContext(localDate: "2026-10-01", tripId: nil, dayId: nil))
        let value = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        XCTAssertEqual(Set(value.keys), ["settings", "messages", "context"])
        let messages = try XCTUnwrap(value["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[0]["role"] as? String, "user")
        XCTAssertTrue(messages[1]["content"] is NSNull)
        XCTAssertTrue((value["context"] as? [String: Any])?["dayId"] is NSNull)
    }
    func testInterruptedBatchIsRepairedWithoutRepeatingWrites() {
        let call = AIMessage.ToolCall(id: "write-1", type: "function", function: .init(name: "create_marker", arguments: "{}"))
        let pending = AIMessage(role: "assistant", content: nil, tool_calls: [call])
        let repaired = AIMessage.repaired([AIMessage(role: "user", content: "保存"), pending])
        XCTAssertEqual(repaired.count, 3)
        XCTAssertEqual(repaired.last?.tool_call_id, "write-1")
        XCTAssertTrue(repaired.last?.content?.contains("不要重复执行") == true)
        XCTAssertEqual(AIMessage.repaired(repaired), repaired)
        XCTAssertTrue(AIMessage.repaired([AIMessage(role: "tool", content: "{}", tool_call_id: "orphan")]).isEmpty)
    }
    func testCreatedHookAcceptsOnlySuccessfulLiveCreationPayloads() throws {
        let places: [[String: Any]] = [["status": "created", "id": "new"], ["status": "existing", "id": "old"], ["status": "created", "id": "new"]]
        for name in ["create_marker", "plan_trip_day"] {
            let inner = try JSONSerialization.data(withJSONObject: name == "create_marker" ? places : ["results": places])
            let data = try JSONSerialization.data(withJSONObject: ["content": [["type": "text", "text": String(decoding: inner, as: UTF8.self)]]])
            var message = AIMessage(role: "tool", content: String(decoding: data, as: UTF8.self), name: name)
            XCTAssertEqual(message.createdMarkerIDs, ["new"])
            message.role = "assistant"; XCTAssertTrue(message.createdMarkerIDs.isEmpty)
            message.role = "tool"; message.name = "list_markers"; XCTAssertTrue(message.createdMarkerIDs.isEmpty)
        }
        let error = AIMessage(role: "tool", content: "{\"isError\":true,\"content\":[]}", name: "create_marker")
        XCTAssertTrue(error.createdMarkerIDs.isEmpty)
    }
    func testDecodesAllNDJSONEventShapes() throws {
        let lines = ["{\"type\":\"delta\",\"text\":\"东京\"}", "{\"type\":\"status\",\"name\":\"create_marker\"}",
            "{\"type\":\"changed\"}", "{\"type\":\"complete\"}", "{\"type\":\"error\",\"message\":\"错误\"}",
            "{\"type\":\"message\",\"message\":{\"role\":\"assistant\",\"content\":null,\"tool_calls\":[]}}"]
        let events = try lines.map { try JSONDecoder().decode(AIEvent.self, from: Data($0.utf8)) }
        XCTAssertEqual(events.map(\.type), ["delta", "status", "changed", "complete", "error", "message"])
        XCTAssertEqual(events[4].error, "错误")
        XCTAssertEqual(events[5].message?.role, "assistant")
    }
    func testConfigurationRejectsEmbeddedCredentialsAndInvalidKeys() throws {
        for url in ["file:///tmp/model", "https://user:password@model.example/v1", "https://model.example/v1?key=x"] {
            XCTAssertThrowsError(try AIConfiguration(baseUrl: url, model: "model").validated())
        }
        XCTAssertThrowsError(try AIConfiguration(apiKey: "a\nb", model: "model").validated())
        XCTAssertEqual(try AIConfiguration(baseUrl: " https://model.example/v1 ", model: " model ").validated().model, "model")
    }
    @MainActor func testEntryRemainsHiddenAndDemoCannotWrite() async {
        XCTAssertTrue(AIPlannerStore.entryEnabled)
        let settings = Settings(), planner = AIPlannerStore()
        await planner.configure(for: settings)
        planner.send("创建旅行", store: AppStore(settings: settings, demo: true))
        XCTAssertFalse(planner.busy)
        XCTAssertTrue(planner.conversations.isEmpty)
        XCTAssertNotNil(planner.error)
    }
}

private final class AIStreamProtocol: URLProtocol {
    static var payload = Data()
    static var status = 200
    static var inspect: ((URLRequest) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.inspect?(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/x-ndjson"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Deliberately split UTF-8 characters and event boundaries.
        for byte in Self.payload { client?.urlProtocol(self, didLoad: Data([byte])) }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private actor AIEventCollector {
    var events: [String] = []
    func append(_ event: AIEvent) { events.append(event.text ?? event.type) }
}
extension AIPlannerTests {
    func testStreamingUsesOnlyServerEndpointAndHandlesSplitUTF8AndPrematureEOF() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AIStreamProtocol.self]
        let service = AIPlannerService(client: APIClient(baseURL: "https://map.invalid", token: "map-token"), sessionConfiguration: configuration)
        let request = AIRequest(settings: AIConfiguration(baseUrl: "https://model.invalid/v1", apiKey: "model-key", model: "test"),
            messages: [AIMessage(role: "user", content: "规划")], context: AIContext(localDate: "2026-10-01", tripId: nil, dayId: nil))
        AIStreamProtocol.status = 200
        AIStreamProtocol.inspect = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://map.invalid/api/ai/chat")
            XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer map-token")
            XCTAssertEqual(req.httpMethod, "POST")
        }
        defer { AIStreamProtocol.inspect = nil }
        AIStreamProtocol.payload = Data("{\"type\":\"delta\",\"text\":\"东京\"}\n{\"type\":\"complete\"}\n".utf8)
        let collector = AIEventCollector()
        try await service.stream(request) { await collector.append($0) }
        let events = await collector.events
        XCTAssertEqual(events, ["东京", "complete"])
        AIStreamProtocol.payload = Data("{\"type\":\"changed\"}\n".utf8)
        do { try await service.stream(request) { _ in }; XCTFail("EOF cannot be reported as success") }
        catch { XCTAssertTrue(error.localizedDescription.contains("中断")) }
        AIStreamProtocol.status = 401
        do { try await service.stream(request) { _ in }; XCTFail("Must reject authentication failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("token")) }
    }
}
