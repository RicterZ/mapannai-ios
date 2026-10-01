import Foundation

struct APIClient {
    let baseURL: String
    let token: String
    var session: URLSession = .shared
    nonisolated func request<T: Decodable>(_ path: String, method: String = "GET", body: [String: Any]? = nil, as: T.Type = T.self) async throws -> T {
        assert(!Thread.isMainThread, "API serialization must stay off the UI thread")
        try Task.checkCancellation()
        guard let base = URL(string: baseURL), let url = URL(string: "\(base.absoluteString)/api/\(path)") else { throw AppError.message("服务地址无效") }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 25
        if !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.message("服务没有返回 HTTP 响应") }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 401 || http.statusCode == 403 { throw AppError.message("认证失败，请检查 API token") }
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw AppError.message(object?["error"] as? String ?? "服务请求失败（\(http.statusCode)）")
        }
        try Task.checkCancellation()
        assert(!Thread.isMainThread, "API decoding must stay off the UI thread")
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw AppError.message("服务返回的数据格式与当前应用不兼容") }
    }
    nonisolated func mutate(_ path: String, method: String, body: [String: Any]? = nil) async throws {
        let _: IgnoredResponse = try await request(path, method: method, body: body)
    }
    nonisolated func deleteDay(tripID: String, dayID: String, deleteExclusiveMarkers: Bool) async throws {
        let suffix = deleteExclusiveMarkers ? "?deleteExclusiveMarkers=true" : ""
        try await mutate("trips/\(Self.id(tripID))/days/\(Self.id(dayID))\(suffix)", method: "DELETE")
    }
    nonisolated func deleteTrip(id: String, deleteExclusiveMarkers: Bool) async throws {
        let suffix = deleteExclusiveMarkers ? "?deleteExclusiveMarkers=true" : ""
        try await mutate("trips/\(Self.id(id))" + suffix, method: "DELETE")
    }
    static func id(_ id: String) -> String { id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id }
    nonisolated func uploadImage(_ data: Data) async throws -> String {
        struct SignedUpload: Decodable { var presignedUrl: String; var publicUrl: String }
        let signed: SignedUpload = try await request("upload", method: "POST", body: ["fileName": "photo.jpg", "fileType": "image/jpeg"])
        guard let url = URL(string: signed.presignedUrl), url.scheme == "https" else { throw AppError.message("上传地址无效") }
        var req = URLRequest(url: url); req.httpMethod = "PUT"; req.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        // The API token must never be sent to COS.
        let (_, response) = try await session.upload(for: req, from: data)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw AppError.message("图片上传失败") }
        return signed.publicUrl
    }
}
struct IgnoredResponse: Decodable { init(from decoder: Decoder) throws {} }
