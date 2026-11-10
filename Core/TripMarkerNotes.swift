import Foundation

enum NoteCoverPatch {
    case omitted
    case set(String?)
}

extension APIClient {
    struct NoteResponse: Decodable { let note: TripMarkerNote? }
    nonisolated func tripMarkerNote(tripID: String, markerID: String, method: String = "GET", title: String? = nil,
                                    content: String? = nil, headerImage: NoteCoverPatch = .omitted, expectedUpdatedAt: String? = nil) async throws -> TripMarkerNote? {
        var body: [String: Any]? = nil
        if method != "GET" {
            body = ["expectedUpdatedAt": expectedUpdatedAt as Any? ?? NSNull()]
            if method == "PATCH" {
                guard let title, let content, title.count <= 200, content.count <= 500_000 else {
                    throw AppError.message("旅行标题最多200字，正文最多500000字")
                }
                if case .set(let image) = headerImage {
                    if let image, !image.isEmpty {
                        guard image.count <= 4096, PlaceImage.httpURL(image) != nil else { throw AppError.message("封面需为HTTP(S)图片，地址最多4096字") }
                    }
                    body?["headerImage"] = image as Any? ?? NSNull()
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
    var headerImage: String?
    var originalHeaderImage: String?
    var originalTitle: String
    var originalContent: String
    var error: String? = nil
    var mustRefresh = false
    var latest: TripMarkerNote? = nil
    var hasLatest = false
    init(note: TripMarkerNote?) {
        title = note?.title ?? ""; content = note?.content ?? ""; version = note?.updatedAt
        headerImage = note?.headerImage; originalHeaderImage = headerImage
        originalTitle = title; originalContent = content
    }
    var changed: Bool { title != originalTitle || content != originalContent || headerImage != originalHeaderImage }
    var coverPatch: NoteCoverPatch { headerImage == originalHeaderImage ? .omitted : .set(headerImage) }
}

/// Shared display policy; editors continue to read the raw fields of their own scope.
enum PlaceImage {
    static func httpURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil else { return nil }
        return url
    }
    private static let imagePattern = try! NSRegularExpression(pattern: #"<img\b[^>]*\bsrc\s*=\s*["']([^"']+)["']"#, options: .caseInsensitive)
    static func firstImage(_ html: String) -> String? {
        guard !html.isEmpty,
              let match = imagePattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html) else { return nil }
        let raw = String(html[range]).replacingOccurrences(of: "&amp;", with: "&")
        return httpURL(raw) == nil ? nil : raw
    }
    static func note(_ note: TripMarkerNote?) -> String? {
        if let image = note?.headerImage, httpURL(image) != nil { return image }
        return firstImage(note?.content ?? "")
    }
    static func image(marker: Marker, trips: [Trip], tripID: String? = nil) -> String? {
        if let tripID { return note(trips.first { $0.id == tripID }?.note(for: marker.id)) }
        let sorted = trips.sorted {
            if $0.startDate != $1.startDate { return $0.startDate > $1.startDate }
            if $0.updatedAt != $1.updatedAt { return ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            return $0.id < $1.id
        }
        if let image = sorted.lazy.compactMap({ note($0.note(for: marker.id)) }).first { return image }
        return general(marker)
    }
    static func general(_ marker: Marker) -> String? {
        if let image = marker.content.headerImage, httpURL(image) != nil { return image }
        return firstImage(marker.content.markdownContent)
    }
}

struct MarkerNoteSelection: Equatable {
    private(set) var initialized = false
    private(set) var tripID: String?
    mutating func initialize(_ defaultID: String?) {
        guard !initialized else { return }
        reset(defaultID)
    }
    mutating func reset(_ defaultID: String?) { initialized = true; tripID = defaultID }
    mutating func select(_ id: String) { initialized = true; tripID = id }
}
