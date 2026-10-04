import Foundation

// Renderers and server-side services are independently selectable, just as in the Web app.
enum MapRendererKind: String, Codable { case amap, apple, google }
enum MapServiceProvider: String, Codable { case amap, google }
struct MapConfiguration: Codable, Equatable {
    var renderer: MapRendererKind
    var searchProvider: MapServiceProvider
    var detailsProvider: MapServiceProvider
    var directionsProvider: MapServiceProvider
    static let current = MapConfiguration(renderer: .amap, searchProvider: .amap, detailsProvider: .amap, directionsProvider: .amap)
}
@MainActor protocol MapConfigurationSource {
    func load(using client: APIClient) async throws -> MapConfiguration
}
// Replace this source with the server configuration source when its endpoint/contract is supplied.
struct FixedMapConfigurationSource: MapConfigurationSource {
    var configuration: MapConfiguration = .current
    func load(using client: APIClient) async throws -> MapConfiguration { configuration }
}

struct SearchBounds: Codable, Equatable {
    var west: Double; var south: Double; var east: Double; var north: Double
    func expanded(factor: Double = 0.2) -> SearchBounds {
        let dx = (east-west)*factor, dy = (north-south)*factor
        return SearchBounds(west: max(-180, west-dx), south: max(-90, south-dy), east: min(180, east+dx), north: min(90, north+dy))
    }
}
struct PlaceSearchRequest {
    var page = 1
    var pageSize = 20
    var pageToken: String?
}
struct PlaceSearchPage {
    var places: [Place]
    var page: Int
    var pageSize: Int
    var nextPage: Int?
    var nextPageToken: String?
}

protocol MapServices {
    func searchPage(_ query: String, bounds: SearchBounds?, request: PlaceSearchRequest) async throws -> PlaceSearchPage
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place]
    func details(at coordinate: Coordinate) async throws -> Place
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TransportMode?) async throws -> PlannedRoute
}
extension MapServices {
    // Compatibility for older implementations: one page, without guessing more.
    nonisolated func searchPage(_ query: String, bounds: SearchBounds?, request: PlaceSearchRequest) async throws -> PlaceSearchPage {
        let places = request.page == 1 ? try await search(query, bounds: bounds) : []
        return PlaceSearchPage(places: places, page: request.page, pageSize: request.pageSize)
    }
}
struct ServerMapServices: MapServices {
    let client: APIClient
    // Metadata isolates cache keys. Existing APIs select their provider on the server.
    let configuration: MapConfiguration
    private struct SearchResponse: Decodable {
        var success: Bool; var data: [SearchResult]
        var page: Int?; var pageSize: Int?; var hasMore: Bool?
        var nextPage: Int?; var nextPageToken: String?
    }
    private struct SearchResult: Decodable {
        var id: String?
        var name: String
        var address: String?
        var coordinates: Coordinate
        var placeId: String?
        var phone: String?
        var placeReferences: PlaceReferences?
        var place: Place {
            let stableID = placeId?.isEmpty == false ? placeId! : "\(name)|\(coordinates.latitude),\(coordinates.longitude)"
            return Place(id: stableID, name: name, address: address ?? "", coordinates: coordinates, phone: phone, placeReferences: placeReferences)
        }
    }
    private struct DetailsResponse: Decodable { var success: Bool; var data: SearchResult }
    nonisolated func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] {
        try await searchPage(query, bounds: bounds, request: PlaceSearchRequest()).places
    }
    nonisolated func searchPage(_ query: String, bounds: SearchBounds?, request: PlaceSearchRequest) async throws -> PlaceSearchPage {
        let page = max(1, request.page), size = min(25, max(1, request.pageSize))
        var parts = URLComponents()
        // limit allows first-page searches against older servers to keep working.
        parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: String(min(20, size))),
                            URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "pageSize", value: String(size))]
        if let token = request.pageToken { parts.queryItems?.append(URLQueryItem(name: "pageToken", value: token)) }
        if let bounds {
            let data = try JSONEncoder().encode(bounds)
            parts.queryItems?.append(URLQueryItem(name: "bounds", value: String(decoding: data, as: UTF8.self)))
        }
        let response: SearchResponse = try await client.request("search?\(parts.percentEncodedQuery ?? "")")
        guard response.success else { throw AppError.message("搜索失败，请重试") }
        let next = response.hasMore == true && (response.nextPage ?? 0) > page ? response.nextPage : nil
        return PlaceSearchPage(places: response.data.filter { $0.coordinates.isValid }.map(\.place),
                               page: response.page ?? page, pageSize: response.pageSize ?? size,
                               nextPage: next, nextPageToken: next == nil ? nil : response.nextPageToken)
    }
    nonisolated func details(at coordinate: Coordinate) async throws -> Place {
        let response: DetailsResponse = try await client.request("places", method: "POST", body: ["latitude": coordinate.latitude, "longitude": coordinate.longitude])
        guard response.success, response.data.coordinates.isValid else { throw AppError.message("未获取到有效地点详情") }
        return response.data.place
    }
    nonisolated func route(_ origin: Coordinate, _ destination: Coordinate, mode: TransportMode?) async throws -> PlannedRoute {
        var body: [String: Any] = ["origin": ["lat": origin.latitude, "lng": origin.longitude],
                                   "destination": ["lat": destination.latitude, "lng": destination.longitude]]
        if let mode { body["transportMode"] = mode.rawValue }
        let route: PlannedRoute = try await client.request("directions", method: "POST", body: body)
        guard route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { throw AppError.message("服务未返回有效路线") }
        return route
    }
}
