import SwiftUI

@MainActor final class AppStore: ObservableObject {
    let settings: Settings
    let configurationSource: any MapConfigurationSource
    private let servicesOverride: (any MapServices)?
    @Published private(set) var mapConfiguration: MapConfiguration = .current
    let routeCache: RouteCache
    private let routeProcessing = RouteProcessing()
    let markerRepository: MarkerRepository
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
    @Published var routeSelectionRequest = UUID()
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
    private var dataRevision = UUID()
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
    init(settings: Settings, demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo"), configurationSource: (any MapConfigurationSource)? = nil, services: (any MapServices)? = nil, markerRepository: MarkerRepository = MarkerRepository(), routeCache: RouteCache = RouteCache()) {
        self.routeCache = routeCache
        self.markerRepository = markerRepository
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
        let revision = connectionRevision, client = api
        if let cached = await markerRepository.cached(using: client), revision == connectionRevision {
            apply(cached)
        }
        guard revision == connectionRevision else { return }
        do { mapConfiguration = try await configurationSource.load(using: api) }
        catch { report(error); return }
        await refresh(force: false, quietly: !markers.isEmpty)
    }
    func refresh(force: Bool = true, quietly: Bool = false) async {
        guard !demo else { rebuildRoutes(); return }
        guard settings.configured, !refreshing, !saving else { return }
        let generation = UUID(); refreshGeneration = generation
        let revision = connectionRevision, client = api
        refreshing = true; if !quietly { loading = true }
        defer { if refreshGeneration == generation { loading = false; refreshing = false } }
        do {
            let value = try await markerRepository.refresh(using: client, force: force)
            guard refreshGeneration == generation, connectionRevision == revision else { return }
            apply(value)
        } catch { if !quietly, refreshGeneration == generation { report(error) } }
    }
    private func apply(_ snapshot: MarkerSnapshot) {
        let changedMarkers = markers != snapshot.markers
        let geometry = Dictionary(markers.map { ($0.id, $0.coordinates) }, uniquingKeysWith: { _, last in last })
        let nextGeometry = Dictionary(snapshot.markers.map { ($0.id, $0.coordinates) }, uniquingKeysWith: { _, last in last })
        let changedTrips = trips != snapshot.trips
        if changedMarkers { markers = snapshot.markers }
        if changedTrips { trips = snapshot.trips }
        if let tripID, !trips.contains(where: { $0.id == tripID }) { self.tripID = nil; dayID = nil }
        if let dayID, !(trip?.days.contains(where: { $0.id == dayID }) ?? false) { self.dayID = nil }
        if let selection = selectedMarker, let updated = markers.first(where: { $0.id == selection.id }) {
            if selection != updated { selectedMarker = updated }
        } else if selectedMarker != nil { selectedMarker = nil }
        if geometry != nextGeometry || changedTrips { rebuildRoutes() }
        applyStartupCamera()
    }
    func refreshSelectedMarker(_ id: String) async {
        guard !demo, settings.configured, !saving else { return }
        let revision = connectionRevision, dataVersion = dataRevision, client = api
        do {
            guard let marker = try await markerRepository.detail(id, using: client), revision == connectionRevision, dataVersion == dataRevision,
                  !saving, let index = markers.firstIndex(where: { $0.id == id }), markers[index] != marker else { return }
            let moved = markers[index].coordinates != marker.coordinates
            markers[index] = marker
            if selectedMarker?.id == id { selectedMarker = marker }
            if moved { rebuildRoutes() }
        } catch { /* Keep cached detail visible on background failure. */ }
    }
    func runBackgroundUpdates() async {
        while !Task.isCancelled {
            await refresh(force: false, quietly: true)
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
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
        guard !saving else { errorMessage = "请等待当前保存完成"; return false }
        // A background read must not block edits or overwrite their results.
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        saving = true; let revision = connectionRevision, client = api
        defer { saving = false }
        await markerRepository.invalidate(using: client)
        do {
            try await operation(client)
            guard revision == connectionRevision else { return false }
            await markerRepository.invalidate(using: client)
            // The mutation has finished; refresh should not be blocked by saving.
            saving = false
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
        rebuildRoutes(preservingPlannedGeometry: true)
        guard focus else { return }
        if let day {
            guard changedDay,
                  let firstID = day.chains.first(where: { !$0.isEmpty })?.first,
                  let marker = markers.first(where: { $0.id == firstID && $0.coordinates.isValid }) else { return }
            camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 15)
        } else if let trip {
            guard let firstDay = trip.days.sorted(by: { $0.date < $1.date }).first else { return }
            let orderedIDs = firstDay.chains.flatMap { $0 } + firstDay.markerIds
            guard let marker = orderedIDs.lazy.compactMap({ id in
                self.markers.first { $0.id == id && $0.coordinates.isValid }
            }).first else { return }
            camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 12)
        } else {
            fly(visibleMarkers.filter { $0.coordinates.isValid }.map(\.coordinates))
        }
    }
    func selectRoute(_ route: DisplayRoute) {
        guard let trip = trips.first(where: { $0.id == route.tripID }), let day = trip.days.first(where: { $0.id == route.dayID }) else { return }
        if tripID != trip.id || dayID != day.id { select(trip: trip, day: day, focus: false) }
        routeSelectionRequest = UUID()
    }
    func focus(_ marker: Marker) {
        guard selectedMarker?.id != marker.id else { return }
        selectedMarker = marker; fly([marker.coordinates])
    }
    func fly(_ points: [Coordinate]) { if !points.isEmpty { camera = CameraCommand(points: points) } }
    func create(at coordinate: Coordinate) {
        guard coordinate.isValid else { return }
        selectedSearchPlaceID = nil; draftExpanded = false
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
            } else { results = try await mapServices.search(query, bounds: bounds?.expanded()) }
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
    func rebuildRoutes(preservingPlannedGeometry: Bool = false) {
        routeTask?.cancel(); let generation = UUID(); routeGeneration = generation
        // Capture immutable inputs before leaving the UI actor. Do not await API work
        // before committing navigation, and do not publish partially built route arrays.
        let days = visibleDays, snapshotMarkers = markers, selectedTrip = trip, previous = displayRoutes
        let planning = settings.planning && !demo
        let mode = settings.mode, services = mapServices, provider = mapConfiguration.directionsProvider, server = settings.baseURL
        routeError = nil; routeProgress = ""
        routeTask = Task {
            defer { if self.routeGeneration == generation { routeProgress = "" } }
            guard var segments = try? await routeProcessing.build(days: days, markers: snapshotMarkers,
                                                                  selectedTrip: selectedTrip, previous: previous,
                                                                  preserve: preservingPlannedGeometry),
                  !Task.isCancelled, self.routeGeneration == generation else { return }
            if planning {
                guard let restored = try? await routeProcessing.restoringCachedGeometry(segments, cache: routeCache,
                            mode: mode, provider: provider, server: server),
                      !Task.isCancelled, self.routeGeneration == generation else { return }
                segments = restored
            }
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { displayRoutes = segments.map(\.display) }
            guard planning, !segments.isEmpty else { return }
            var failed = 0, completed = 0
            for segment in segments {
                let display = segment.display, a = segment.origin, b = segment.destination
                guard !Task.isCancelled, self.routeGeneration == generation else { return }
                let key = RouteCache.key(a, b, mode: mode, provider: provider, server: server)
                do {
                    var route = await routeCache.get(key)
                    if route == nil {
                        route = try await services.route(a, b, mode: mode)
                        try Task.checkCancellation()
                        guard self.routeGeneration == generation else { return }
                        if let route { await routeCache.put(route, key: key) }
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                    guard let route else { continue }
                    let points = try await routeProcessing.displayPoints(route, origin: a, destination: b)
                    guard !Task.isCancelled, self.routeGeneration == generation else { return }
                    if let index = displayRoutes.firstIndex(where: { $0.id == display.id }) {
                        var updated = displayRoutes[index]
                        if updated.points != points || updated.isPlanned != !route.isFallback {
                            updated.points = points; updated.isPlanned = !route.isFallback
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) { displayRoutes[index] = updated }
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

    func awaitRouteUpdates() async { await routeTask?.value }

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
        if ProcessInfo.processInfo.arguments.contains("--long-title-demo") {
            trips[0].name = "呼和浩特·大同美食行"
        }
        if ProcessInfo.processInfo.arguments.contains("--scroll-demo") {
            // Read-only long lists for navigation/scroll regression checks.
            let memberIDs = markers.map(\.id)
            trips = (1...12).map { number in
                let id = "scroll-trip-\(number)"
                let date = String(format: "2026-%02d-01", number)
                let longDays = (1...12).map { day in
                    TripDay(id: "\(id)-day-\(day)", tripId: id, date: String(format: "2026-%02d-%02d", number, day),
                            title: "第\(day)天", colorIndex: day, markerIds: memberIDs,
                            chains: Array(repeating: memberIDs, count: 4))
                }
                return Trip(id: id, name: "示例旅行 \(number)", startDate: date,
                            endDate: String(format: "2026-%02d-12", number), days: longDays)
            }
            tripID = nil; dayID = nil
        } else {
            tripID = trips.first?.id; dayID = days.first?.id
        }
        rebuildRoutes(); fly(markers.map(\.coordinates))
    }
}
struct CameraCommand: Identifiable {
    var id = UUID()
    var points: [Coordinate]
    var singlePointZoom: Double = 15
    // Single places always use an absolute level, never the previous map scale.
    var zoomLevel: Double? { points.count == 1 ? singlePointZoom : nil }
}
