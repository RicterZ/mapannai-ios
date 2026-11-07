import Foundation

extension APIClient {
    struct NoteResponse: Decodable { let note: TripMarkerNote? }
    nonisolated func tripMarkerNote(tripID: String, markerID: String, method: String = "GET", title: String? = nil,
                                    content: String? = nil, expectedUpdatedAt: String? = nil) async throws -> TripMarkerNote? {
        var body: [String: Any]? = nil
        if method != "GET" {
            body = ["expectedUpdatedAt": expectedUpdatedAt as Any? ?? NSNull()]
            if method == "PATCH" {
                guard let title, let content, title.count <= 200, content.count <= 500_000 else {
                    throw AppError.message("旅行标题最多200字，正文最多500000字")
                }
                body?["title"] = title; body?["content"] = content
            }
        }
        let response: NoteResponse = try await request("trips/\(Self.id(tripID))/markers/\(Self.id(markerID))/note", method: method, body: body)
        guard response.note == nil || (response.note?.tripId == tripID && response.note?.markerId == markerID) else {
            throw AppError.message("服务返回的旅行笔记归属不匹配")
        }
        return response.note
    }
}

// Match the server: notes protect places even after all itinerary membership is removed.
extension Trip {
    static func exclusiveMarkerIDs(trips: [Trip], tripID: String, dayID: String?) -> Set<String> {
        guard let owner = trips.first(where: { $0.id == tripID }) else { return [] }
        let removed = owner.days.filter { dayID == nil || $0.id == dayID }
        let candidates = dayID == nil ? owner.referencedMarkerIDs : Set(removed.flatMap { $0.markerIds + $0.chains.flatMap { $0 } })
        var retained = Set<String>()
        for trip in trips {
            if dayID == nil && trip.id == tripID { continue }
            retained.formUnion(trip.markerIds ?? [])
            retained.formUnion(trip.notes.map(\.markerId))
            for day in trip.days where !(trip.id == tripID && day.id == dayID) {
                retained.formUnion(day.markerIds + day.chains.flatMap { $0 })
            }
        }
        return candidates.subtracting(retained)
    }
}

struct TripNoteEditDraft: Equatable {
    var title: String
    var content: String
    var version: String?
    var originalTitle: String
    var originalContent: String
    var error: String? = nil
    var mustRefresh = false
    var latest: TripMarkerNote? = nil
    var hasLatest = false
    init(note: TripMarkerNote?) {
        title = note?.title ?? ""; content = note?.content ?? ""; version = note?.updatedAt
        originalTitle = title; originalContent = content
    }
    var changed: Bool { title != originalTitle || content != originalContent }
}
