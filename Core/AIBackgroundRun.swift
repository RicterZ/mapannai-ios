import Foundation

struct AIBackgroundRun: Codable {
    var id: String?
    let token: String
    let requestID: UUID
    var cursor = 0
    var partial = ""
    var prompt: AIInteractionPrompt?
    var context: AIContext? = nil
    var model: String? = nil
    var modelBaseURL: String? = nil
    enum CodingKeys: String, CodingKey { case id, requestID, cursor, partial, prompt, context, model, modelBaseURL }
    init(token: String, requestID: UUID) { self.token = token; self.requestID = requestID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        requestID = try c.decode(UUID.self, forKey: .requestID)
        token = Keychain.read("ai-run-" + requestID.uuidString)
        cursor = try c.decode(Int.self, forKey: .cursor)
        partial = try c.decode(String.self, forKey: .partial)
        context = try c.decodeIfPresent(AIContext.self, forKey: .context)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        modelBaseURL = try c.decodeIfPresent(String.self, forKey: .modelBaseURL)
        if let saved = try c.decodeIfPresent(AIInteractionPrompt.self, forKey: .prompt) {
            prompt = AIInteractionPrompt(id: saved.id, token: Keychain.read("ai-interaction-" + saved.id), deadline: saved.deadline, input: saved.input)
        }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(id, forKey: .id); try c.encode(requestID, forKey: .requestID)
        try c.encode(cursor, forKey: .cursor); try c.encode(partial, forKey: .partial)
        try c.encodeIfPresent(context, forKey: .context); try c.encodeIfPresent(model, forKey: .model)
        try c.encodeIfPresent(modelBaseURL, forKey: .modelBaseURL)
        if let prompt {
            try c.encode(AIInteractionPrompt(id: prompt.id, token: "", deadline: prompt.deadline, input: prompt.input), forKey: .prompt)
        }
    }
}

struct AIBackgroundPage: Decodable {
    struct Item: Decodable { let seq: Int; let event: AIEvent }
    let status: String
    let events: [Item]
    let cursor: Int
}

extension AIPlannerService {
    nonisolated func backgroundRequest(method: String, path: String, token: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: client.baseURL + "/api/ai/runs" + path) else { throw AppError.message("服务地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body; request.timeoutInterval = 20
        request.setValue(token, forHTTPHeaderField: "x-run-token")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !client.token.isEmpty { request.setValue("Bearer " + client.token, forHTTPHeaderField: "Authorization") }
        let session = URLSession(configuration: sessionConfiguration ?? .ephemeral, delegate: AITransportDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("服务响应无效") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { throw AppError.message("规划服务或记录不可用，请确认服务端已更新") }
            throw AppError.message("规划请求失败（HTTP \(http.statusCode)）")
        }
        guard data.count <= 40_000_000 else { throw AppError.message("规划结果过长") }
        return data
    }
    nonisolated func startRun(_ request: AIRequest, token: String) async throws -> String {
        struct Started: Decodable { let id: String }
        let body = try JSONEncoder().encode(request)
        guard body.count <= 2_000_000 else { throw AppError.message("聊天记录过长，请新建会话") }
        let data = try await backgroundRequest(method: "POST", path: "", token: token, body: body)
        let id = try JSONDecoder().decode(Started.self, from: data).id
        guard id.count == 48, id.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw AppError.message("规划记录标识无效") }
        return id
    }
    nonisolated func readRun(_ run: AIBackgroundRun) async throws -> AIBackgroundPage {
        guard let id = run.id else { throw AppError.message("规划尚未开始") }
        return try JSONDecoder().decode(AIBackgroundPage.self, from: await backgroundRequest(method: "GET", path: "/" + id + "?after=\(run.cursor)", token: run.token))
    }
    nonisolated func cancelRun(_ run: AIBackgroundRun) async throws {
        guard let id = run.id else { return }
        _ = try await backgroundRequest(method: "DELETE", path: "/" + id, token: run.token)
    }
}
