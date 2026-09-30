import Foundation
import CryptoKit

struct MarkerSnapshot: Codable {
    var markers: [Marker]
    var trips: [Trip]
    var fetchedAt: Date
}

// Actor isolates network/decode/file work from UI and merges concurrent requests.
actor MarkerRepository {
    private let directory: URL
    private var snapshots: [String: MarkerSnapshot] = [:]
    private var listTasks: [String: Task<MarkerSnapshot, Error>] = [:]
    private var detailTasks: [String: Task<Marker, Error>] = [:]
    private var detailAttempts: [String: Date] = [:]
    private var generations: [String: UUID] = [:]
    init(directory: URL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MarkerSnapshots", isDirectory: true)) {
        self.directory = directory
    }
    static func scope(_ client: APIClient) -> String {
        // Credentials are never persisted. Hash scopes isolate servers/accounts.
        SHA256.hash(data: Data((client.baseURL + "\n" + client.token).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func cached(using client: APIClient) -> MarkerSnapshot? {
        let key = Self.scope(client)
        if let value = snapshots[key] { return value }
        guard let data = try? Data(contentsOf: file(key)), let value = try? JSONDecoder().decode(MarkerSnapshot.self, from: data) else { return nil }
        snapshots[key] = value
        return value
    }
    func refresh(using client: APIClient, force: Bool = false) async throws -> MarkerSnapshot {
        let key = Self.scope(client)
        if let task = listTasks[key] { return try await task.value }
        if !force, let value = cached(using: client), Date().timeIntervalSince(value.fetchedAt) < 60 { return value }
        let generation = generations[key] ?? UUID(); generations[key] = generation
        let task = Task<MarkerSnapshot, Error> {
            async let markers: [Marker] = client.request("markers")
            async let trips: [Trip] = client.request("trips")
            return try await MarkerSnapshot(markers: markers, trips: trips, fetchedAt: Date())
        }
        listTasks[key] = task
        do {
            let value = try await task.value
            guard generations[key] == generation else { throw CancellationError() }
            listTasks[key] = nil
            snapshots[key] = value
            generations[key] = UUID()
            // List refresh supersedes older single-point requests.
            for detailKey in Array(detailTasks.keys) where detailKey.hasPrefix(key + "/") {
                detailTasks.removeValue(forKey: detailKey)?.cancel()
            }
            persist(value, key: key)
            return value
        } catch {
            if generations[key] == generation { listTasks[key] = nil }
            throw error
        }
    }
    func detail(_ id: String, using client: APIClient) async throws -> Marker? {
        let key = Self.scope(client), detailKey = Self.scope(client) + "/" + id
        if let task = detailTasks[detailKey] { _ = try await task.value; return nil }
        if let attempt = detailAttempts[detailKey], Date().timeIntervalSince(attempt) < 30 { return nil }
        // A fresh full list already contains the details; do not immediately fetch again.
        if let value = cached(using: client), Date().timeIntervalSince(value.fetchedAt) < 30 { return nil }
        detailAttempts[detailKey] = Date()
        let generation = generations[key] ?? UUID(); generations[key] = generation
        let task = Task<Marker, Error> { try await client.request("markers/" + APIClient.id(id)) }
        detailTasks[detailKey] = task
        do {
            var marker = try await task.value
            try Task.checkCancellation()
            guard generations[key] == generation, detailTasks[detailKey] != nil else { return nil }
            detailTasks[detailKey] = nil
            guard marker.id == id else { return nil }
            if var value = snapshots[key], let index = value.markers.firstIndex(where: { $0.id == id }) {
                if marker.content.address == nil { marker.content.address = value.markers[index].content.address }
                if value.markers[index] != marker {
                    value.markers[index] = marker; snapshots[key] = value; persist(value, key: key)
                }
            }
            return marker
        } catch {
            if generations[key] == generation { detailTasks[detailKey] = nil }
            throw error
        }
    }
    func invalidate(using client: APIClient) {
        _ = cached(using: client)
        let key = Self.scope(client)
        generations[key] = UUID()
        listTasks.removeValue(forKey: key)?.cancel()
        for detailKey in Array(detailTasks.keys) where detailKey.hasPrefix(key + "/") {
            detailTasks.removeValue(forKey: detailKey)?.cancel()
        }
        detailAttempts = detailAttempts.filter { !$0.key.hasPrefix(key + "/") }
        // Keep cached content available, but require refresh after mutations.
        if var value = snapshots[key] { value.fetchedAt = .distantPast; snapshots[key] = value; persist(value, key: key) }
    }
    private func file(_ key: String) -> URL { directory.appendingPathComponent(key + ".json") }
    private func persist(_ value: MarkerSnapshot, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: file(key), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var url = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try? url.setResourceValues(flags)
    }
}
