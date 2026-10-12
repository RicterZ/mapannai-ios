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
struct TripDestination: Codable, Hashable {
    let name: String
    let latitude: Double
    let longitude: Double
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 200 &&
        latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
    var coordinateKey: String { String(format: "%.6f:%.6f", latitude, longitude) }
    var requestBody: [String: Any] { ["name": name, "latitude": latitude, "longitude": longitude] }
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
    var destination: TripDestination? = nil
    var destinations: [TripDestination]? = nil
    var selectedDestinations: [TripDestination] { destinations ?? destination.map { [$0] } ?? [] }
}
extension Trip {
    var minimumEditableDayCount: Int {
        max(days.count, TripDateRange(savedStart: .fromDay(startDate), savedEnd: .fromDay(endDate)).dayCount)
    }
    func edited(name: String, emoji: String, start: Date, end: Date) throws -> Trip {
        guard start.dayString <= end.dayString else { throw AppError.message("结束日期不能早于开始日期") }
        let range = TripDateRange(savedStart: start, savedEnd: end)
        guard range.isValid else { throw AppError.message("一次最多安排 367 天") }
        guard range.dayCount >= minimumEditableDayCount else {
            throw AppError.message("至少保留原有 \(minimumEditableDayCount) 天，可整体改期或延长旅途")
        }
        var result = self
        result.name = name; result.emoji = emoji; result.startDate = start.dayString; result.endDate = end.dayString
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
        result.days = days.sorted { $0.date < $1.date }.enumerated().map { index, day in
            var shifted = day
            shifted.date = utc.date(byAdding: .day, value: index, to: start)!.dayString
            return shifted
        }
        for index in result.days.count..<range.dayCount {
            result.days.append(TripDay(id: "pending-day-" + UUID().uuidString, tripId: id,
                date: utc.date(byAdding: .day, value: index, to: start)!.dayString, markerIds: [], chains: []))
        }
        return result
    }
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
    /// Only newly joined members take the default route; existing placements stay put.
    func addingToDefaultRoute(_ ids: [String]) -> TripDay {
        var copy = self
        let additions = ids.reduce(into: [String]()) { result, id in
            if !copy.markerIds.contains(id), !result.contains(id) { result.append(id) }
        }
        copy.markerIds.append(contentsOf: additions)
        guard !additions.isEmpty, copy.chains.count <= 1 else { return copy }
        copy.setRouteOrders(copy.chains.isEmpty ? [additions] : [copy.chains[0] + additions])
        return copy
    }
    func replacingChain(at index: Int?, with ids: [String]) throws -> TripDay {
        guard !ids.isEmpty, Set(ids).count == ids.count else { throw AppError.message("请选择至少一个地点，且不能重复") }
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
        // Single-stop routes are valid for both creation and editing.
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
    var distanceKind: String? = nil
    var isFallback: Bool { fallback != nil }
}
struct Place: Identifiable, Hashable {
    var id: String
    var name: String
    var address: String
    var coordinates: Coordinate
    var phone: String?
    var placeReferences: PlaceReferences? = nil
    var markerId: String? = nil
    var types: [String] = []
    var rating: Double? = nil
    var categoryLabel: String? {
        let labels = ["lodging": "住宿", "hotel": "酒店", "restaurant": "餐厅", "food": "美食",
                      "cafe": "咖啡馆", "tourist_attraction": "景点", "park": "公园",
                      "museum": "博物馆", "shopping_mall": "购物中心", "store": "商店",
                      "train_station": "火车站", "transit_station": "车站", "airport": "机场",
                      "place_of_worship": "宗教场所", "natural_feature": "自然景观"]
        for type in types {
            let value = type.trimmingCharacters(in: .whitespacesAndNewlines)
            if let label = labels[value.lowercased()] { return label }
            if value.range(of: "[\\p{Han}\\p{Hiragana}\\p{Katakana}]", options: .regularExpression) != nil { return value }
        }
        return nil
    }
}

enum PlaceSearchMerger {
    static func merge(query: String, markers: [Marker], places: [Place]) -> [Place] {
        func key(_ coordinate: Coordinate) -> String {
            "\((coordinate.longitude * 1_000_000).rounded())|\((coordinate.latitude * 1_000_000).rounded())"
        }
        func place(_ marker: Marker) -> Place {
            Place(id: "marker:\(marker.id)", name: marker.title, address: marker.content.address ?? "",
                  coordinates: marker.coordinates, markerId: marker.id)
        }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return [] }
        var coordinates: [String: Marker] = [:]
        for marker in markers where marker.coordinates.isValid {
            if coordinates[key(marker.coordinates)] == nil { coordinates[key(marker.coordinates)] = marker }
        }
        var results = markers.filter { $0.coordinates.isValid && $0.title.lowercased().contains(keyword) }.map(place)
        var ids = Set(results.map(\.id))
        for result in places where result.coordinates.isValid {
            var item = coordinates[key(result.coordinates)].map(place) ?? result
            if item.markerId != nil {
                item.types = result.types; item.rating = result.rating; item.phone = result.phone
                item.placeReferences = result.placeReferences
            }
            if ids.insert(item.id).inserted { results.append(item) }
            else if let index = results.firstIndex(where: { $0.id == item.id }) {
                results[index] = item
            }
        }
        return results
    }
}
struct DisplayRoute: Identifiable {
    var id: String
    var dayID: String
    var tripID: String
    var colorIndex: Int
    var points: [Coordinate]
    var isPlanned: Bool
    var distance: Double? = nil
    var transportMode: TransportMode? = nil
    var isDashed = false
    var unseparatedPoints: [Coordinate]? = nil
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
