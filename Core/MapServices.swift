import Foundation

// Renderers and server-side services are independently selectable, just as in the Web app.
enum MapRendererKind: String, Codable { case amap, google }
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

struct SearchBounds: Codable {
    var west: Double; var south: Double; var east: Double; var north: Double
    func expanded() -> SearchBounds {
        let dx = (east-west)*0.2, dy = (north-south)*0.2
        return SearchBounds(west: max(-180, west-dx), south: max(-90, south-dy), east: min(180, east+dx), north: min(90, north+dy))
    }
}
protocol MapServices {
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place]
    func details(at coordinate: Coordinate) async throws -> Place
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TravelMode) async throws -> PlannedRoute
}
struct ServerMapServices: MapServices {
    let client: APIClient
    // Metadata isolates cache keys. Existing APIs select their provider on the server.
    let configuration: MapConfiguration
    private struct SearchResponse: Decodable { var success: Bool; var data: [SearchResult] }
    private struct SearchResult: Decodable {
        var id: String?
        var name: String
        var address: String?
        var coordinates: Coordinate
        var placeId: String?
        var phone: String?
        var place: Place {
            Place(id: placeId ?? id ?? "\(coordinates.latitude),\(coordinates.longitude)", name: name,
                  address: address ?? "", coordinates: coordinates, phone: phone)
        }
    }
    private struct DetailsResponse: Decodable { var success: Bool; var data: SearchResult }
    func search(_ query: String, bounds: SearchBounds?) async throws -> [Place] {
        var parts = URLComponents(); parts.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20")]
        if let bounds {
            let data = try JSONEncoder().encode(bounds.expanded())
            parts.queryItems?.append(URLQueryItem(name: "bounds", value: String(decoding: data, as: UTF8.self)))
        }
        let response: SearchResponse = try await client.request("search?\(parts.percentEncodedQuery ?? "")")
        guard response.success else { throw AppError.message("搜索失败，请重试") }
        return response.data.filter { $0.coordinates.isValid }.map(\.place)
    }
    func details(at coordinate: Coordinate) async throws -> Place {
        let response: DetailsResponse = try await client.request("places", method: "POST", body: ["latitude": coordinate.latitude, "longitude": coordinate.longitude])
        guard response.success, response.data.coordinates.isValid else { throw AppError.message("未获取到有效地点详情") }
        return response.data.place
    }
    func route(_ origin: Coordinate, _ destination: Coordinate, mode: TravelMode) async throws -> PlannedRoute {
        let route: PlannedRoute = try await client.request("directions", method: "POST", body: ["origin": ["lat": origin.latitude, "lng": origin.longitude], "destination": ["lat": destination.latitude, "lng": destination.longitude], "mode": mode.resolved(from: origin, to: destination).rawValue])
        guard route.path.count > 1, route.path.allSatisfy({ $0.coordinate.isValid }) else { throw AppError.message("服务未返回有效路线，请尝试另一种出行方式") }
        return route
    }
}
