import Foundation
import CryptoKit

struct AIConfiguration: Codable, Equatable {
    var baseUrl = "https://api.openai.com/v1"
    var apiKey = ""
    var model = ""
    func validated() throws -> Self {
        var value = self
        value.baseUrl = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        value.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URLComponents(string: value.baseUrl), ["https", "http"].contains(url.scheme ?? ""),
              url.host != nil, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              value.baseUrl.count <= 2048, !value.model.isEmpty, value.model.count <= 200,
              apiKey.count <= 4096, !apiKey.contains("\n"), !apiKey.contains("\r") else {
            throw AppError.message("请填写有效的 API 地址和模型，地址不能包含凭据或查询参数")
        }
        return value
    }
}

struct AIMessage: Codable, Equatable {
    struct ToolCall: Codable, Equatable {
        struct Function: Codable, Equatable { var name: String; var arguments: String }
        var id: String
        var type: String
        var function: Function
    }
    var role: String
    var content: String?
    var tool_calls: [ToolCall]? = nil
    var tool_call_id: String? = nil
    var name: String? = nil
    enum CodingKeys: String, CodingKey { case role, content, tool_calls, tool_call_id, name }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(role, forKey: .role)
        try c.encode(content, forKey: .content) // assistant tool-only replies require explicit null
        try c.encodeIfPresent(tool_calls, forKey: .tool_calls)
        try c.encodeIfPresent(tool_call_id, forKey: .tool_call_id)
        try c.encodeIfPresent(name, forKey: .name)
    }

    var createdMarkerIDs: [String] {
        guard role == "tool", ["create_marker", "plan_trip_day"].contains(name ?? ""),
              let bytes = content?.data(using: .utf8),
              let result = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              result["isError"] as? Bool != true else { return [] }
        var ids: [String] = []
        for part in result["content"] as? [[String: Any]] ?? [] {
            guard part["type"] as? String == "text", let text = part["text"] as? String,
                  let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) else { continue }
            let places = value as? [[String: Any]] ?? (value as? [String: Any])?["results"] as? [[String: Any]] ?? []
            for place in places where place["status"] as? String == "created" {
                if let id = place["id"] as? String, !ids.contains(id) { ids.append(id) }
            }
        }
        return ids
    }
    // Preserve unknown tool outcomes; never replay writes after cancellation/reconnect.
    static func repaired(_ messages: [Self]) -> [Self] {
        var result: [Self] = [], pending: [ToolCall] = []
        func flush() {
            result += pending.map { Self(role: "tool", content: "{\"error\":\"上次请求已中断，此工具结果未知；先查询实际数据，不要重复执行写入操作。\"}", tool_call_id: $0.id, name: $0.function.name) }
            pending = []
        }
        for message in messages {
            if message.role == "tool" {
                guard let index = pending.firstIndex(where: { $0.id == message.tool_call_id }) else { continue }
                pending.remove(at: index); result.append(message)
            } else {
                flush(); result.append(message)
                if message.role == "assistant" { pending = message.tool_calls ?? [] }
            }
        }
        flush(); return result
    }
}
struct AIEvent: Decodable {
    var type: String
    var text: String?
    var name: String?
    var message: AIMessage?
    var error: String?
    enum CodingKeys: String, CodingKey { case type, text, name, message }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decode(String.self, forKey: .type)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        if type == "error" { error = try c.decode(String.self, forKey: .message) }
        else { message = try c.decodeIfPresent(AIMessage.self, forKey: .message) }
    }
}
struct AIContext: Codable {
    var localDate: String
    var tripId: String?
    var dayId: String?
    enum CodingKeys: String, CodingKey { case localDate, tripId, dayId }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(localDate, forKey: .localDate)
        try c.encode(tripId, forKey: .tripId); try c.encode(dayId, forKey: .dayId)
    }
}
struct AIRequest: Encodable {
    var settings: AIConfiguration
    var messages: [AIMessage]
    var context: AIContext
}
// No cross-host redirects: this body contains the upstream API key.
final class AITransportDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
struct AIPlannerService {
    var client: APIClient
    var sessionConfiguration: URLSessionConfiguration? = nil
    nonisolated func stream(_ input: AIRequest, receive: @escaping @Sendable (AIEvent) async throws -> Void) async throws {
        let body = try JSONEncoder().encode(input)
        guard body.count <= 2_000_000, let url = URL(string: client.baseURL + "/api/ai/chat") else {
            throw AppError.message("聊天记录过长或服务地址无效，请新建会话")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.httpBody = body; request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
        if !client.token.isEmpty { request.setValue("Bearer " + client.token, forHTTPHeaderField: "Authorization") }
        let config = sessionConfiguration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 150; config.timeoutIntervalForResource = 2100
        let session = URLSession(configuration: config, delegate: AITransportDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("服务没有返回有效响应") }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 || http.statusCode == 403 { throw AppError.message("认证失败，请检查 MapAnNai API token") }
            if http.statusCode == 404 { throw AppError.message("当前服务尚未提供 AI 助手，请更新 MapAnNai Plus") }
            throw AppError.message("AI 请求失败（HTTP \(http.statusCode)），请检查 API 地址、模型和服务配置")
        }
        guard http.value(forHTTPHeaderField: "Content-Type")?.contains("application/x-ndjson") == true else {
            throw AppError.message("服务未返回 AI 流式协议，请更新 MapAnNai Plus")
        }
        var complete = false
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if line.isEmpty { continue }
            guard line.utf8.count <= 2_000_000 else { throw AppError.message("AI 返回内容过长") }
            let event = try JSONDecoder().decode(AIEvent.self, from: Data(line.utf8))
            if event.type == "error" { throw AppError.message(event.error ?? "AI 请求失败") }
            try await receive(event)
            if event.type == "complete" { complete = true; break }
        }
        if !complete { throw AppError.message("回复已中断；部分操作可能已保存，请查询后继续") }
    }
}

struct AIConversation: Codable, Identifiable {
    var id = UUID()
    var title = "新会话"
    var messages: [AIMessage] = []
}
actor AIHistoryRepository {
    private var revisions: [String: Int] = [:]
    private func url(_ scope: String) throws -> URL {
        let root = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("AIHistory", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root.appendingPathComponent(scope + ".json")
    }
    func read(_ scope: String) throws -> [AIConversation] {
        let path = try url(scope)
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        return try JSONDecoder().decode([AIConversation].self, from: Data(contentsOf: path))
    }
    func write(_ conversations: [AIConversation], scope: String, revision: Int) throws {
        guard revision >= revisions[scope, default: 0] else { return }
        revisions[scope] = revision
        let data = try JSONEncoder().encode(conversations)
        try data.write(to: url(scope), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

@MainActor final class AIPlannerStore: ObservableObject {
    // Deliberately hidden until enabled in a later product release. UI tests can open directly.
    static let entryEnabled = true
    @Published var presented = false
    @Published var configuration = AIConfiguration()
    @Published var conversations: [AIConversation] = []
    @Published var activeID: UUID?
    @Published var partial = ""
    @Published var status = ""
    @Published var error: String?
    @Published var storageError: String?
    @Published private(set) var busy = false
    @Published private(set) var ready = false
    var conversation: AIConversation? { conversations.first { $0.id == activeID } }
    private var task: Task<Void, Never>?
    private var effectsTask: Task<Void, Never>?
    private var needsRefresh = false
    private var createdIDs: [String] = []
    private var generation = UUID()
    private weak var activeStore: AppStore?
    private var scope = ""
    private var saveRevision = 0
    private let history = AIHistoryRepository()

    func configure(for settings: Settings) async {
        activeStore = nil; presented = false; stop()
        let oldEffects = effectsTask; oldEffects?.cancel()
        generation = UUID(); let revision = generation
        await oldEffects?.value
        guard generation == revision else { return }
        effectsTask = nil; needsRefresh = false; createdIDs = []
        ready = false; conversations = []; activeID = nil; partial = ""; error = nil; storageError = nil
        scope = SHA256.hash(data: Data((settings.baseURL + "|" + settings.token).utf8)).map { String(format: "%02x", $0) }.joined()
        configuration = AIConfiguration(baseUrl: UserDefaults.standard.string(forKey: "ai-base-" + scope) ?? "https://api.openai.com/v1",
            apiKey: Keychain.read("ai-key-" + scope), model: UserDefaults.standard.string(forKey: "ai-model-" + scope) ?? "")
        do {
            let saved = try await history.read(scope)
            guard generation == revision else { return }
            conversations = saved; activeID = saved.first?.id; ready = true
        } catch { if generation == revision { storageError = "无法读取本地会话，原记录已保留" } }
    }
    func saveConfiguration(_ draft: AIConfiguration) throws {
        let value = try draft.validated()
        guard !scope.isEmpty else { throw AppError.message("请先连接 MapAnNai 服务") }
        try Keychain.write(value.apiKey, key: "ai-key-" + scope)
        UserDefaults.standard.set(value.baseUrl, forKey: "ai-base-" + scope)
        UserDefaults.standard.set(value.model, forKey: "ai-model-" + scope)
        configuration = value
    }
    private func persist() {
        guard ready else { return }
        saveRevision += 1
        let data = conversations, key = scope, revision = saveRevision
        Task {
            do { try await history.write(data, scope: key, revision: revision) }
            catch { if scope == key { storageError = "会话未能保存到设备，当前聊天仍可继续" } }
        }
    }
    func clearUnreadableHistory() {
        guard !busy else { return }
        conversations = []; activeID = nil; ready = true; storageError = nil; persist()
    }
    func newConversation() {
        guard !busy, ready else { return }
        guard conversations.count < 20 else { error = "最多保留20个会话，请先删除旧会话"; return }
        let next = AIConversation(); conversations.insert(next, at: 0); activeID = next.id
        partial = ""; error = nil; persist()
    }
    func deleteConversation() {
        guard !busy else { return }
        conversations.removeAll { $0.id == activeID }; activeID = conversations.first?.id; persist()
    }
    func stop() {
        task?.cancel(); task = nil; generation = UUID()
        if busy { error = "已停止；正在执行的操作可能已保存，请查询后继续" }
        busy = false; partial = ""
        createdIDs = []
        if let store = activeStore { queueRefresh(store: store, ids: []) }
    }
    func close() { presented = false; stop() }
    func send(_ text: String, store: AppStore) {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, ready, !input.isEmpty else { return }
        guard store.settings.configured, !store.demo else { error = "请连接服务后使用 AI 规划；示例模式不写入数据"; return }
        do { configuration = try configuration.validated() } catch { self.error = error.localizedDescription; return }
        guard input.count <= 30_000 else { error = "消息过长，请分开发送"; return }
        if conversation == nil { newConversation() }
        guard let index = conversations.firstIndex(where: { $0.id == activeID }) else { return }
        var messages = AIMessage.repaired(conversations[index].messages)
        guard messages.count < 180 else { error = "会话较长，请新建会话继续"; return }
        messages.append(AIMessage(role: "user", content: input))
        if conversations[index].messages.isEmpty { conversations[index].title = String(input.prefix(40)) }
        conversations[index].messages = messages; persist()
        let id = conversations[index].id
        let revision = UUID(); generation = revision
        busy = true; error = nil; partial = ""; status = "正在思考…"
        let request = AIRequest(settings: configuration, messages: messages,
            context: AIContext(localDate: StartupCamera.localDate(now: Date(), calendar: .current), tripId: store.tripID, dayId: store.dayID))
        let service = AIPlannerService(client: store.api)
        activeStore = store
        task = Task {
            do {
                try await service.stream(request) { [self, store] event in
                    await self.receive(event, id: id, revision: revision, store: store)
                }
            } catch {
                if generation == revision {
                    let message = error.localizedDescription
                    self.error = !configuration.apiKey.isEmpty && message.contains(configuration.apiKey) ? "AI 请求失败，请检查配置" : message
                }
            }
            guard generation == revision else { return }
            busy = false; task = nil; partial = ""
            queueRefresh(store: store, ids: []) // Includes partial writes and unexpected disconnects.
        }
    }
    private func receive(_ event: AIEvent, id: UUID, revision: UUID, store: AppStore?) {
        guard generation == revision, let index = conversations.firstIndex(where: { $0.id == id }) else { return }
        switch event.type {
        case "delta": partial += event.text ?? ""; status = "正在回复…"
        case "status": status = "正在处理行程…"
        case "message":
            guard let message = event.message else { return }
            if message.role == "assistant" { partial = "" }
            conversations[index].messages.append(message); persist()
            if let store, !message.createdMarkerIDs.isEmpty { queueRefresh(store: store, ids: message.createdMarkerIDs) }
        case "changed": if let store { queueRefresh(store: store, ids: []) }
        default: break
        }
    }
    private func queueRefresh(store: AppStore, ids: [String]) {
        needsRefresh = true; createdIDs += ids
        guard effectsTask == nil else { return }
        let key = scope
        effectsTask = Task { [weak self, weak store] in
            guard let self, let store else { return }
            defer { self.effectsTask = nil }
            while self.needsRefresh, !Task.isCancelled, self.scope == key {
                self.needsRefresh = false
                let ids = self.createdIDs; self.createdIDs = []
                let responseGeneration = self.generation
                let cameraBeforeRefresh = store.camera?.id
                let conversationBeforeRefresh = self.activeID
                await store.refreshAfterAIChange()
                guard !Task.isCancelled, self.scope == key, self.presented, self.generation == responseGeneration, store.camera?.id == cameraBeforeRefresh, self.activeID == conversationBeforeRefresh else { continue }
                let markers = ids.compactMap { id in store.markers.first { $0.id == id } }
                if !markers.isEmpty { store.fly(markers.map(\.coordinates)) }
            }
        }
    }
}
