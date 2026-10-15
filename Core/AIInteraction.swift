import Foundation

struct AIInteractionPrompt: Codable, Identifiable {
    struct Input: Codable {
        struct Option: Codable, Identifiable { let id: String; let label: String; let description: String? }
        struct Day: Codable { let date: String; let title: String; let places: [String] }
        let kind: String
        let question: String
        var multiple: Bool?
        var maxSelections: Int?
        var options: [Option]?
        var mode: String?
        var timezone: String?
        var title: String?
        var days: [Day]?
    }
    let id: String
    let token: String
    let deadline: Double
    let input: Input
    var expires: Date { Date(timeIntervalSince1970: deadline / 1000) }
    var supported: Bool {
        switch input.kind {
        case "ask_choice":
            guard let options = input.options, (2...20).contains(options.count) else { return false }
            return Set(options.map(\.id)).count == options.count && (1...20).contains(input.maxSelections ?? 1)
        case "ask_datetime": return ["date", "date_range", "time", "datetime", "datetime_range"].contains(input.mode ?? "") && TimeZone(identifier: input.timezone ?? "") != nil
        case "preview_itinerary": return !(input.days ?? []).isEmpty && (input.days?.count ?? 0) <= 90
        default: return false
        }
    }
    func validate(_ selection: AIInteractionSelection) throws {
        guard supported else { throw AppError.message("当前交互暂不支持，请在聊天中补充") }
        switch (input.kind, selection) {
        case ("ask_choice", .choices(let ids)):
            guard !ids.isEmpty, ids.count <= (input.multiple == true ? input.maxSelections ?? 1 : 1),
                  Set(ids).count == ids.count, ids.allSatisfy({ id in input.options?.contains { $0.id == id } == true }) else {
                throw AppError.message("请完成有效选择后提交")
            }
        case ("ask_datetime", .datetime(let start, let end)):
            let mode = input.mode ?? "date", range = mode.hasSuffix("_range")
            let format = mode == "time" ? "HH:mm" : mode.hasPrefix("datetime") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
            let formatter = Self.formatter(format: format, timezone: input.timezone ?? "UTC")
            for value in [start] + (range ? [end ?? ""] : []) {
                guard let date = formatter.date(from: value), formatter.string(from: date) == value else {
                    throw AppError.message("请选择有效的日期和时间")
                }
            }
            guard !range || (end ?? "") >= start else { throw AppError.message("结束时间不能早于开始时间") }
        case ("preview_itinerary", .preview(let action, let feedback)):
            guard ["continue", "revise"].contains(action), feedback.count <= 2000 else { throw AppError.message("调整意见最多2000字") }
        default: throw AppError.message("交互内容不匹配")
        }
    }
    static func formatter(format: String, timezone: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = format
        formatter.isLenient = false
        return formatter
    }
}

enum AIInteractionSelection: Codable {
    case choices([String])
    case datetime(start: String, end: String?)
    case preview(action: String, feedback: String)
    private enum CodingKeys: String, CodingKey { case start, end, action, feedback }
    init(from decoder: Decoder) throws {
        if let ids = try? decoder.singleValueContainer().decode([String].self) { self = .choices(ids); return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let action = try c.decodeIfPresent(String.self, forKey: .action) {
            self = .preview(action: action, feedback: try c.decode(String.self, forKey: .feedback))
        } else {
            self = .datetime(start: try c.decode(String.self, forKey: .start), end: try c.decodeIfPresent(String.self, forKey: .end))
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .choices(let ids): var c = encoder.singleValueContainer(); try c.encode(ids)
        case .datetime(let start, let end):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(start, forKey: .start); try c.encodeIfPresent(end, forKey: .end)
        case .preview(let action, let feedback):
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(action, forKey: .action); try c.encode(feedback, forKey: .feedback)
        }
    }
}

extension AIPlannerService {
    nonisolated func submitInteraction(_ prompt: AIInteractionPrompt, selection: AIInteractionSelection) async throws {
        try prompt.validate(selection)
        guard prompt.expires > Date() else { throw AppError.message("此选择已结束，请在聊天中补充") }
        struct Answer: Encodable { let id: String; let token: String; let selection: AIInteractionSelection }
        guard let url = URL(string: client.baseURL + "/api/ai/interactions") else { throw AppError.message("服务地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"; request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !client.token.isEmpty { request.setValue("Bearer " + client.token, forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(Answer(id: prompt.id, token: prompt.token, selection: selection))
        let session = URLSession(configuration: sessionConfiguration ?? .ephemeral, delegate: AITransportDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("服务没有返回有效响应") }
        guard (200..<300).contains(http.statusCode) else {
            throw AppError.message(http.statusCode == 409 ? "此选择已结束，请在聊天中补充" : "提交失败（HTTP \(http.statusCode)），请重试")
        }
    }
}

struct AIInteractionRecord: Codable, Identifiable {
    let id: String
    let input: AIInteractionPrompt.Input
    let messageIndex: Int
    var selection: AIInteractionSelection?
    var ended = false
    var prompt: AIInteractionPrompt { AIInteractionPrompt(id: id, token: "", deadline: 0, input: input) }
}
