import Foundation

struct Coordinate: Codable, Hashable {
    var latitude: Double
    var longitude: Double
    var isValid: Bool { latitude.isFinite && longitude.isFinite && abs(latitude) <= 90 && abs(longitude) <= 180 }
}

enum MarkerIcon: String, Codable, CaseIterable, Identifiable {
    case activity, location, hotel, shopping, food, landmark, park, natural, culture, transit
    var id: String { rawValue }
    var label: String {
        switch self {
        case .activity: "活动"; case .location: "地点"; case .hotel: "住宿"; case .shopping: "购物"
        case .food: "美食"; case .landmark: "地标"; case .park: "公园"; case .natural: "自然"
        case .culture: "人文"; case .transit: "交通"
        }
    }
    var emoji: String {
        switch self {
        case .activity: "🎯"; case .location: "📍"; case .hotel: "🏨"; case .shopping: "🛍️"
        case .food: "🍜"; case .landmark: "🌆"; case .park: "🎡"; case .natural: "🗻"
        case .culture: "⛩️"; case .transit: "🚉"
        }
    }
    var colorRGB: UInt32 {
        switch self {
        case .activity: 0xF97316; case .location: 0xEC4899; case .hotel: 0x22C55E
        case .shopping, .landmark: 0xA855F7; case .food: 0x71717A; case .park: 0x64748B
        case .natural: 0xD946EF; case .culture: 0x6B7280; case .transit: 0x3B82F6
        }
    }
    var symbol: String {
        switch self {
        case .activity: "sparkles"; case .location: "mappin"; case .hotel: "bed.double.fill"
        case .shopping: "bag.fill"; case .food: "fork.knife"; case .landmark: "building.2.fill"
        case .park: "tree.fill"; case .natural: "mountain.2.fill"; case .culture: "building.columns.fill"
        case .transit: "tram.fill"
        }
    }
}
struct MarkerContent: Codable, Hashable {
    var id: String
    var title: String?
    var address: String?
    var headerImage: String?
    var iconType: MarkerIcon?
    var markdownContent: String
    var createdAt: String?
    var updatedAt: String?
}
struct PlaceReference: Codable, Hashable {
    var placeId: String
}
struct PlaceReferences: Codable, Hashable {
    var apple: PlaceReference? = nil
    var google: PlaceReference? = nil
    var amap: PlaceReference? = nil
    var requestBody: [String: Any] {
        var result: [String: Any] = [:]
        if let apple { result["apple"] = ["placeId": apple.placeId] }
        if let google { result["google"] = ["placeId": google.placeId] }
        if let amap { result["amap"] = ["placeId": amap.placeId] }
        return result
    }
}
struct Marker: Codable, Identifiable, Hashable {
    var id: String
    var coordinates: Coordinate
    var content: MarkerContent
    var placeReferences: PlaceReferences? = nil
    var title: String { content.title ?? "未命名地点" }
    var icon: MarkerIcon { content.iconType ?? .location }
}
struct Trip: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var description: String?
    var startDate: String
    var endDate: String
    var coverImage: String?
    var emoji: String?
    var days: [TripDay]
    var markerIds: [String]? = nil
}
struct TripDay: Codable, Identifiable, Hashable {
    var id: String
    var tripId: String
    var date: String
    var title: String?
    var emoji: String?
    var colorIndex: Int?
    var markerIds: [String]
    var chains: [[String]]
    var routeChains: [RouteChain]? = nil
    var label: String { title?.isEmpty == false ? title! : date }
    func scheduledRoute(at index: Int) -> RouteChain? {
        guard chains.indices.contains(index) else { return nil }
        let ids = chains[index]
        if let routes = routeChains, routes.indices.contains(index), routes[index].stops.map(\.markerId) == ids { return routes[index] }
        return routeChains?.first { $0.stops.map(\.markerId) == ids }
    }
    func removing(_ markerID: String) -> TripDay {
        var copy = self
        copy.markerIds.removeAll { $0 == markerID }
        copy.setRouteOrders(chains.map { $0.filter { $0 != markerID } })
        return copy
    }
    func replacingChain(at index: Int?, with ids: [String]) throws -> TripDay {
        guard ids.count >= 2, Set(ids).count == ids.count else { throw AppError.message("路线至少需要两个不同地点") }
        var copy = self
        for id in ids where !copy.markerIds.contains(id) { copy.markerIds.append(id) }
        if let index {
            guard copy.chains.indices.contains(index) else { throw AppError.message("路线已发生变化，请重新打开") }
            var orders = copy.chains; orders[index] = ids; copy.setRouteOrders(orders)
        } else { copy.setRouteOrders(copy.chains + [ids]) }
        return copy
    }
}
/// A local route draft; day membership and other routes remain untouched until save.
struct RouteEditSession: Equatable {
    let day: TripDay
    let index: Int?
    var ids: [String]
    var slot: Int { index ?? day.chains.count }
    mutating func move(_ id: String, to target: String) {
        guard let from = ids.firstIndex(of: id), let to = ids.firstIndex(of: target), from != to else { return }
        ids.remove(at: from); ids.insert(id, at: to)
    }
    func applying(to latest: TripDay) throws -> TripDay {
        guard latest.id == day.id, latest.tripId == day.tripId, latest.chains == day.chains else {
            throw AppError.message("路线已更新，请取消编辑后重试")
        }
        if let index, !latest.chains.indices.contains(index) { throw AppError.message("路线已发生变化，请取消编辑后重试") }
        if let index, ids.isEmpty {
            var updated = latest; updated.removeRoute(at: index); return updated
        }
        // Existing single-stop routes are valid; new routes still need two stops.
        if let index, ids.count == 1 {
            var updated = latest; var orders = updated.chains; orders[index] = ids; updated.setRouteOrders(orders); return updated
        }
        return try latest.replacingChain(at: index, with: ids)
    }
}
struct RoutePoint: Codable, Hashable {
    var lat: Double
    var lng: Double
    var coordinate: Coordinate { Coordinate(latitude: lat, longitude: lng) }
}
struct PlannedRoute: Codable {
    var path: [RoutePoint]
    var distance: Double?
    var duration: Double?
    var fallback: String? = nil
    var isFallback: Bool { fallback == "OVER_DIRECTION_RANGE" || fallback == "UNSUPPORTED_REGION" }
}
struct Place: Identifiable, Hashable {
    var id: String
    var name: String
    var address: String
    var coordinates: Coordinate
    var phone: String?
    var placeReferences: PlaceReferences? = nil
}
struct DisplayRoute: Identifiable {
    var id: String
    var dayID: String
    var tripID: String
    var colorIndex: Int
    var points: [Coordinate]
    var isPlanned: Bool
    var distance: Double? = nil
    var unseparatedPoints: [Coordinate]? = nil
}
enum TravelMode: String, Codable, CaseIterable { case auto, walking, driving
    var label: String { switch self { case .auto: "自动"; case .walking: "步行"; case .driving: "驾车" } }
    func resolved(from a: Coordinate, to b: Coordinate) -> TravelMode {
        guard self == .auto else { return self }
        return (Coordinates.distance(a, b) * 1_000_000).rounded() < 2_000 * 1_000_000 ? .walking : .driving
    }
}
enum AppError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let value) = self { return value }; return nil }
}
struct MarkerDraft: Identifiable {
    var id = UUID()
    var marker: Marker?
    var placeReferences: PlaceReferences? = nil
    var coordinates: Coordinate
    var title: String = ""
    var address: String = ""
    var icon: MarkerIcon = .location
    var html: String = ""
    var headerImage: String = ""
    var resolvingPlace = false
    var placeLookupFailed = false
    init(coordinates: Coordinate, title: String = "", address: String = "", placeReferences: PlaceReferences? = nil) {
        self.placeReferences = placeReferences
        self.coordinates = coordinates; self.title = title; self.address = address
    }
    init(marker: Marker) {
        self.placeReferences = marker.placeReferences
        self.marker = marker; coordinates = marker.coordinates; title = marker.title
        address = marker.content.address ?? ""; icon = marker.icon
        html = marker.content.markdownContent; headerImage = marker.content.headerImage ?? ""
    }
}
extension Date {
    var dayString: String { Self.dayFormatter.string(from: self) }
    static func fromDay(_ value: String) -> Date { dayFormatter.date(from: value) ?? .now }
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
}
