import XCTest
@testable import MapAnNai

final class AIPlannerTests: XCTestCase {
    @MainActor func testTitleEventUpdatesRequestConversationNotActiveConversation() throws {
        let planner = AIPlannerStore()
        let request = AIConversation(), active = AIConversation()
        planner.conversations = [request, active]
        planner.activeID = active.id
        let event = try JSONDecoder().decode(AIEvent.self, from: Data(#"{"type":"title","title":" 京都慢逛与小店 "}"#.utf8))
        planner.updateConversationTitle(event.title, id: request.id)
        XCTAssertEqual(planner.conversations[0].title, "京都慢逛与小店")
        XCTAssertEqual(planner.conversation?.title, "新会话")
        for title in [nil, "   ", String(repeating: "a", count: 61)] {
            planner.updateConversationTitle(title, id: request.id)
        }
        planner.updateConversationTitle("不存在", id: UUID())
        XCTAssertEqual(planner.conversations[0].title, "京都慢逛与小店")
        XCTAssertTrue(planner.conversations[0].messages.isEmpty)
    }

    func testToolLabelsTranslateKnownNamesAndPreserveUnknownNames() {
        XCTAssertEqual(AIToolLabel.text("search_places"), "搜索地点")
        XCTAssertEqual(AIToolLabel.text("plan_trip_day"), "规划当天行程")
        XCTAssertEqual(AIToolLabel.text("search_web"), "搜索网页")
        XCTAssertEqual(AIToolLabel.text("fetch_web"), "读取网页")
        XCTAssertEqual(AIToolLabel.text("future_tool"), "future_tool")
    }
    func testAllRegisteredMCPToolsHaveLocalizedLabels() {
        let tools = ["list_markers", "create_marker", "update_marker", "delete_marker",
            "search_destinations", "search_places", "search_web", "fetch_web", "get_place_details", "get_directions",
            "get_walking_directions", "list_trips", "get_trip_detail", "create_trip", "add_day_to_trip",
            "assign_marker_to_trip", "remove_marker_from_trip", "assign_marker_to_day", "plan_trip_day",
            "create_day_chain", "update_day_chain", "delete_day_chain", "reorder_day_markers", "delete_trip", "change_title"]
        for name in tools { XCTAssertNotEqual(AIToolLabel.text(name), name, name) }
    }
    @MainActor func testClosingKeepsReplyRunningAndReopeningPreservesConversation() async throws {
        let planner = AIPlannerStore()
        let conversation = AIConversation()
        planner.conversations = [conversation]
        planner.activeID = conversation.id
        planner.presented = true
        let stream = Task { await planner.previewStreamingReply() }
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertTrue(planner.busy)
        let received = planner.partial
        planner.close()
        XCTAssertFalse(planner.presented)
        XCTAssertTrue(planner.busy)
        XCTAssertEqual(planner.partial, received)
        XCTAssertNil(planner.error)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertGreaterThan(planner.partial.count, received.count)
        planner.presented = true
        XCTAssertEqual(planner.activeID, conversation.id)
        await stream.value
        XCTAssertFalse(planner.busy)
        XCTAssertTrue(planner.conversation?.messages.last?.content?.contains("完成末尾") == true)
    }
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
        XCTAssertEqual(Set(value.keys), ["settings", "messages", "context", "supportsInteractions"])
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
        XCTAssertFalse(AIPlannerStore.entryEnabled)
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

extension AIPlannerTests {
    func testInteractionSubmissionUsesExistingAuthenticatedEndpoint() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [AIStreamProtocol.self]
        let service = AIPlannerService(client: APIClient(baseURL: "https://map.invalid", token: "map-token"), sessionConfiguration: config)
        let data = Data(#"{"id":"prompt","token":"ephemeral-test","deadline":2000000000000,"input":{"kind":"ask_choice","question":"偏好","options":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"multiple":false,"maxSelections":1}}"#.utf8)
        let prompt = try JSONDecoder().decode(AIInteractionPrompt.self, from: data)
        AIStreamProtocol.payload = Data()
        AIStreamProtocol.status = 204
        AIStreamProtocol.inspect = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://map.invalid/api/ai/interactions")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer map-token")
        }
        defer { AIStreamProtocol.inspect = nil; AIStreamProtocol.status = 200 }
        try await service.submitInteraction(prompt, selection: .choices(["a"]))
        AIStreamProtocol.status = 409
        do {
            try await service.submitInteraction(prompt, selection: .choices(["a"]))
            XCTFail("Expired interaction must fail")
        } catch { XCTAssertTrue(error.localizedDescription.contains("已结束")) }
        let request = AIRequest(settings: AIConfiguration(), messages: [], context: AIContext(localDate: "2026-10-15", tripId: nil, dayId: nil))
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        XCTAssertEqual(json?["supportsInteractions"] as? Bool, true)
        XCTAssertEqual(AIMessage(role: "tool", content: #"{"status":"timed_out"}"#, name: "ask_choice").interactionSummary, "未选择，改用文字说明")
    }
}
