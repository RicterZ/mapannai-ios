import SwiftUI

@MainActor final class AppStore: ObservableObject {
    let settings: Settings
    let configurationSource: any MapConfigurationSource
    private let servicesOverride: (any MapServices)?
    @Published private(set) var mapConfiguration: MapConfiguration = .current
    let routeCache = RouteCache()
    @Published var markers: [Marker] = []
    @Published var trips: [Trip] = []
    @Published var tripID: String?
    @Published var dayID: String?
    @Published var selectedMarker: Marker?
    @Published var draft: MarkerDraft?
    @Published var draftExpanded = true
    @Published var selectedSearchPlaceID: String?
    @Published var searchResults: [Place] = []
    @Published var searchText = ""
    @Published var searching = false
    @Published var loading = false
    @Published var saving = false
    @Published var errorMessage: String?
    @Published var routeError: String?
    @Published var routeCandidates: [DisplayRoute] = []
    @Published var displayRoutes: [DisplayRoute] = []
    @Published var routeProgress = ""
    @Published var camera: CameraCommand?
    @Published var locating = UUID()
    @Published var mapViewportInsets: MapViewportInsets = .phone
    var bounds: SearchBounds?
    let demo: Bool
    private var routeTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var searchGeneration = UUID()
    private var routeGeneration = UUID()
    private var connectionRevision = UUID()
    private var refreshing = false
    private var startupCameraPending = true
    var api: APIClient { APIClient(baseURL: settings.baseURL, token: settings.token) }
    var mapServices: any MapServices { servicesOverride ?? ServerMapServices(client: api, configuration: mapConfiguration) }
    var trip: Trip? { trips.first { $0.id == tripID } }
    var day: TripDay? { trip?.days.first { $0.id == dayID } }
    var visibleDays: [TripDay] {
        if let day { return [day] }
        if let trip { return trip.days }
        return trips.flatMap(\.days)
    }
    var mapMarkers: [Marker] { markers }
    var visibleMarkers: [Marker] {
        guard tripID != nil else { return markers }
        let ids = Set(visibleDays.flatMap(\.markerIds)); return markers.filter { ids.contains($0.id) }
    }
    init(settings: Settings, demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo"), configurationSource: (any MapConfigurationSource)? = nil, services: (any MapServices)? = nil) {
        self.settings = settings; self.demo = demo; self.servicesOverride = services; self.configurationSource = configurationSource ?? FixedMapConfigurationSource()
        if demo { loadDemo() }
    }
    func connect() async {
        connectionRevision = UUID(); refreshGeneration = UUID(); loading = false; refreshing = false
        tripID = nil; dayID = nil; selectedMarker = nil; selectedSearchPlaceID = nil; searchResults = []; markers = []; trips = []
        camera = nil; startupCameraPending = true
        searchGeneration = UUID(); searching = false; rebuildRoutes()
        if demo { loadDemo(); rebuildRoutes(); return }
        guard settings.configured else { return }
        do { mapConfiguration = try await configurationSource.load(using: api) }
        catch { report(error); return }
        await refresh()
    }
    func refresh() async {
        guard !demo else { rebuildRoutes(); return }
        let generation = UUID(); refreshGeneration = generation; loading = true; refreshing = true
        let client = api
        defer { if refreshGeneration == generation { loading = false; refreshing = false } }
        do {
            async let fetchedMarkers: [Marker] = client.request("markers")
            async let fetchedTrips: [Trip] = client.request("trips")
            let (newMarkers, newTrips) = try await (fetchedMarkers, fetchedTrips)
            guard refreshGeneration == generation else { return }
            markers = newMarkers; trips = newTrips
            if let tripID, !trips.contains(where: { $0.id == tripID }) { self.tripID = nil; dayID = nil }
            if let dayID, !(trip?.days.contains(where: { $0.id == dayID }) ?? false) { self.dayID = nil }
            if let selection = selectedMarker { selectedMarker = markers.first { $0.id == selection.id } }
            rebuildRoutes()
            applyStartupCamera()
        } catch { if refreshGeneration == generation { report(error) } }
    }
    func applyStartupCamera(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        guard startupCameraPending else { return }
        startupCameraPending = false
        // Do not interrupt a selection or camera action made while data was loading.
        guard tripID == nil, dayID == nil, selectedMarker == nil, draft == nil, camera == nil else { return }
        if let marker = StartupCamera.upcomingFirstMarker(trips: trips, markers: markers,
                                                          today: StartupCamera.localDate(now: now, calendar: calendar)) {
            camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 11)
        }
    }
    func perform(_ operation: @escaping (APIClient) async throws -> Void) async -> Bool {
        guard !demo else { errorMessage = "当前为只读示例。配置服务后退出示例模式，即可保存到你的数据库。"; return false }
        guard !saving, !refreshing else { errorMessage = "请等待当前同步完成"; return false }
        saving = true; let revision = connectionRevision, client = api
        defer { saving = false }
        do {
            try await operation(client)
            guard revision == connectionRevision else { return false }
            await refresh(); return true
        } catch { if revision == connectionRevision { report(error) }; return false }
    }
    func saveMarker(_ draft: MarkerDraft) async -> Bool {
        guard draft.coordinates.isValid, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入名称与有效坐标"; return false }
        let targetDay = draft.marker == nil ? day : nil
        let ok = await perform { client in
            if let marker = draft.marker {
                try await client.mutate("markers/\(APIClient.id(marker.id))", method: "PUT", body: ["title": draft.title, "iconType": draft.icon.rawValue, "markdownContent": draft.html, "headerImage": draft.headerImage])
            } else {
                let created: Marker = try await client.request("markers", method: "POST", body: ["coordinates": ["latitude": draft.coordinates.latitude, "longitude": draft.coordinates.longitude], "title": draft.title, "iconType": draft.icon.rawValue, "address": draft.address, "content": draft.html])
                if !draft.headerImage.isEmpty { try await client.mutate("markers/\(APIClient.id(created.id))", method: "PUT", body: ["headerImage": draft.headerImage]) }
                if let targetDay { try await client.mutate(Self.dayPath(targetDay) + "/markers", method: "POST", body: ["markerId": created.id]) }
            }
        }
        if ok { self.draft = nil }; return ok
    }
    func deleteMarker(_ marker: Marker) async {
        if await perform({ try await $0.mutate("markers/\(APIClient.id(marker.id))", method: "DELETE") }) { selectedMarker = nil }
    }
    func updateDay(_ day: TripDay) async -> Bool {
        let body: [String: Any] = ["title": day.title ?? "", "emoji": day.emoji ?? "", "markerIds": day.markerIds, "chains": day.chains]
        return await perform { try await $0.mutate(Self.dayPath(day), method: "PUT", body: body) }
    }
    static func dayPath(_ day: TripDay) -> String { "trips/\(APIClient.id(day.tripId))/days/\(APIClient.id(day.id))" }
    @discardableResult func addMarker(_ marker: Marker, to day: TripDay) async -> Bool {
        return await perform { try await $0.mutate(Self.dayPath(day) + "/markers", method: "POST", body: ["markerId": marker.id]) }
    }
    func removeMarker(_ markerID: String, from day: TripDay) async {
        _ = await perform { try await $0.mutate(Self.dayPath(day) + "/markers", method: "DELETE", body: ["markerId": markerID]) }
    }
    func select(trip: Trip?, day: TripDay? = nil, focus: Bool = true) {
        let changedDay = tripID != trip?.id || dayID != day?.id
        tripID = trip?.id; dayID = day?.id; selectedMarker = nil
        rebuildRoutes()
        guard focus else { return }
        if let day {
            guard changedDay,
                  let firstID = day.chains.first(where: { !$0.isEmpty })?.first,
                  let marker = markers.first(where: { $0.id == firstID && $0.coordinates.isValid }) else { return }
            camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 15)
        } else {
            fly(visibleMarkers.filter { $0.coordinates.isValid }.map(\.coordinates))
        }
    }
    func selectRoute(_ route: DisplayRoute) {
        if dayID == route.dayID { return }
        guard let trip = trips.first(where: { $0.id == route.tripID }), let day = trip.days.first(where: { $0.id == route.dayID }) else { return }
        select(trip: trip, day: day, focus: false)
    }
    func focus(_ marker: Marker) {
        guard selectedMarker?.id != marker.id else { return }
        selectedMarker = marker; fly([marker.coordinates])
    }
    func fly(_ points: [Coordinate]) { if !points.isEmpty { camera = CameraCommand(points: points) } }
    func create(at coordinate: Coordinate) {
        guard coordinate.isValid else { return }
        selectedSearchPlaceID = nil; draftExpanded = true
        var pending = MarkerDraft(coordinates: coordinate)
        pending.resolvingPlace = true
        draft = pending
        let draftID = pending.id
        Task {
            do {
                let place = try await mapServices.details(at: coordinate)
                guard self.draft?.id == draftID else { return }
                self.draft?.title = place.name
                self.draft?.address = place.address
                self.draft?.resolvingPlace = false
            } catch {
                guard self.draft?.id == draftID else { return }
                self.draft?.resolvingPlace = false
                self.draft?.placeLookupFailed = true
            }
        }
    }
    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { clearSearch(); return }
        let generation = UUID(); searchGeneration = generation; searching = true; searchResults = []; selectedSearchPlaceID = nil
        defer { if searchGeneration == generation { searching = false } }
        do {
            let results: [Place]
            if demo && servicesOverride == nil {
                results = markers.filter { $0.title.localizedCaseInsensitiveContains(query) }.map {
                    Place(id: $0.id, name: $0.title, address: $0.content.address ?? "", coordinates: $0.coordinates)
                }
            } else { results = try await mapServices.search(query, bounds: bounds) }
            guard searchGeneration == generation else { return }; searchResults = results
            fly(results.map(\.coordinates))
            if results.isEmpty { errorMessage = "当前地图范围内没有结果。可移动地图或使用更精确的城市与地点名称。" }
        } catch { if searchGeneration == generation { report(error) } }
    }
    func clearSearch() { searchGeneration = UUID(); searchText = ""; searchResults = []; selectedSearchPlaceID = nil; searching = false }
    func choose(_ place: Place, fromMap: Bool = false) {
        guard place.coordinates.isValid else { return }
        if fromMap, selectedSearchPlaceID == place.id, draft != nil {
            draftExpanded = true
            return
        }
        selectedSearchPlaceID = place.id; draftExpanded = false
        fly([place.coordinates])
        draft = MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
    }
    func report(_ error: Error) { if error is CancellationError { return }; errorMessage = error.localizedDescription }
    func rebuildRoutes() {
        routeTask?.cancel(); let generation = UUID(); routeGeneration = generation
        let segments = visibleDays.flatMap { day in
            day.chains.enumerated().flatMap { chainIndex, chain -> [(DisplayRoute, Coordinate, Coordinate)] in
                guard chain.count > 1 else { return [] }
                return (1..<chain.count).compactMap { i in
                    guard let a = markers.first(where: { $0.id == chain[i-1] }), let b = markers.first(where: { $0.id == chain[i] }) else { return nil }
                    let display = DisplayRoute(id: "\(day.id)|\(chainIndex)|\(i)|\(a.id)|\(b.id)", dayID: day.id, tripID: day.tripId,
                                               colorIndex: day.colorIndex ?? (trip?.days.firstIndex(where: { $0.id == day.id }) ?? 0),
                                               points: RouteGeometry.curve(a.coordinates, b.coordinates), isPlanned: false)
                    return (display, a.coordinates, b.coordinates)
                }
            }
        }
        displayRoutes = segments.map(\.0); routeError = nil; routeProgress = ""
        guard settings.planning, !demo, !segments.isEmpty else { return }
        let mode = settings.mode, services = mapServices, provider = mapConfiguration.directionsProvider, server = settings.baseURL
        routeTask = Task {
            defer { if self.routeGeneration == generation { routeProgress = "" } }
            var failed = 0, completed = 0
            for (display, a, b) in segments {
                guard !Task.isCancelled, self.routeGeneration == generation else { return }
                let key = RouteCache.key(a, b, mode: mode, provider: provider, server: server)
                do {
                    var route = routeCache.get(key)
                    if route == nil {
                        route = try await services.route(a, b, mode: mode)
                        if let route { routeCache.put(route, key: key) }
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                    guard !Task.isCancelled, self.routeGeneration == generation else { return }
                    if let route, let index = displayRoutes.firstIndex(where: { $0.id == display.id }) {
                        if route.isFallback {
                            displayRoutes[index].points = RouteGeometry.curve(a, b)
                            displayRoutes[index].isPlanned = false
                        } else {
                            var points = route.path.map(\.coordinate)
                            // Preserve itinerary endpoints even when the SDK snaps them onto a road.
                            points.insert(a, at: 0); points.append(b)
                            displayRoutes[index].points = RouteGeometry.smooth(points); displayRoutes[index].isPlanned = true
                        }
                    }
                } catch {
                    if Task.isCancelled || self.routeGeneration != generation { return }
                    failed += 1; routeError = "\(failed) 段暂未完成"
                }
                completed += 1; routeProgress = "\(completed)/\(segments.count)"
            }
        }
    }
    private func loadDemo() {
        let names = ["武康大楼", "武康庭", "安福路", "静安寺", "愚园路"]
        let coordinates = [(31.2050,121.4353),(31.2090,121.4365),(31.2140,121.4400),(31.2232,121.4450),(31.2250,121.4380)]
        markers = names.enumerated().map { i, name in
            Marker(id: "demo-\(i)", coordinates: Coordinate(latitude: coordinates[i].0, longitude: coordinates[i].1),
                   content: MarkerContent(id: "demo-\(i)", title: name, address: "上海市", iconType: i == 1 ? .food : .landmark,
                                          markdownContent: i == 0 ? "<p><br></p>" : "<p>示例地点笔记。</p>"))
        }
        let days = [TripDay(id: "day-1", tripId: "demo-trip", date: "2026-10-01", title: "梧桐街区漫步", colorIndex: 0, markerIds: ["demo-0","demo-1","demo-2"], chains: [["demo-0","demo-1","demo-2"]]),
                    TripDay(id: "day-2", tripId: "demo-trip", date: "2026-10-02", title: "城市与旧时光", colorIndex: 1, markerIds: ["demo-2","demo-3","demo-4"], chains: [["demo-2","demo-3","demo-4"]])]
        trips = [Trip(id: "demo-trip", name: "上海 · 秋日散步", description: "示例行程", startDate: "2026-10-01", endDate: "2026-10-02", emoji: "🍂", days: days)]
        tripID = trips.first?.id; dayID = days.first?.id; rebuildRoutes(); fly(markers.map(\.coordinates))
    }
}
struct CameraCommand: Identifiable {
    var id = UUID()
    var points: [Coordinate]
    var singlePointZoom: Double = 15
    // Single places always use an absolute level, never the previous map scale.
    var zoomLevel: Double? { points.count == 1 ? singlePointZoom : nil }
}
