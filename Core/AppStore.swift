import SwiftUI
import MapKit

struct TripSaveDraft: Identifiable {
    var id = UUID()
    let trip: Trip?
    let name: String
    let start: Date
    let end: Date
    let emoji: String
    var destinations: [TripDestination] = []
}

struct DayEditorDraft: Identifiable {
    var id = UUID()
    let tripID: String
    let day: TripDay?
    let date: String
    var title: String
    var markerIDs: [String]
}

@MainActor final class AppStore: ObservableObject {
    private var appleMapItems: [String: (coordinate: Coordinate, references: PlaceReferences?, item: MKMapItem)] = [:]
    func appleMapItem(for marker: Marker) -> MKMapItem? {
        guard let cached = appleMapItems[marker.id], cached.coordinate == marker.coordinates, cached.references == marker.placeReferences else { return nil }
        return cached.item
    }
    private var applePOIRequest: (draftID: UUID, coordinate: Coordinate, revision: UUID, task: Task<MKMapItem?, Never>)?
    func resolveApplePOI(_ feature: MKMapFeatureAnnotation) {
        guard let draft else { return }
        applePOIRequest?.task.cancel()
        let request = MKMapItemRequest(mapFeatureAnnotation: feature)
        let task = Task<MKMapItem?, Never> {
            await withTaskCancellationHandler {
                try? await request.mapItem
            } onCancel: { request.cancel() }
        }
        applePOIRequest = (draft.id, draft.coordinates, connectionRevision, task)
        Task {
            guard let item = await task.value, !task.isCancelled,
                  self.draft?.id == draft.id, self.draft?.coordinates == draft.coordinates,
                  self.applePOIRequest?.revision == self.connectionRevision else { return }
            if #available(iOS 18.0, *), let id = item.identifier?.rawValue {
                self.draft?.placeReferences = PlaceReferences(apple: PlaceReference(placeId: id))
            }
        }
    }
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
    @Published var dayMapBrowsing = false
    @Published private(set) var dayMapFocusID: String?
    @Published private(set) var dayMapCameraFollowing = true
    var mapHighlightedMarkerID: String? { selectedMarker?.id ?? (dayMapBrowsing ? dayMapFocusID : nil) }
    @Published var selectedMarker: Marker?
    @Published var tripSaveRecovery: TripSaveDraft?
    @Published var dayEditorDraft: DayEditorDraft?
    private var pendingCreatedDays: [UUID: TripDay] = [:]
    @Published private(set) var canResumeFailedSave = false
    private var failedSaveAction: (() -> Void)?
    private var pendingCreatedMarkers: [UUID: Marker] = [:]
    private var pendingCreatedTrips: [UUID: Trip] = [:]
    @Published var draft: MarkerDraft?
    @Published var draftExpanded = true
    @Published var selectedSearchPlaceID: String?
    @Published private(set) var placeSearchPresented = false
    @Published var previewTripPlaces: [String: [Marker]] = [:]
    var tripPlacesPreview: Bool { demo && ProcessInfo.processInfo.arguments.contains("--trip-places-preview") }
    @Published var addPlaceTripID: String?
    @Published var addPlaceDay: TripDay?
    @Published var addPlaceError: String?
    @Published private(set) var addingPlaceID: String?
    @Published private(set) var addedPlaceIDs: Set<String> = []
    @Published var editingSearchPlaceID: String?
    @Published private(set) var searchError: String?
    private var addSession = UUID()
    private var createdSearchMarkers: [String: Marker] = [:]
    @Published var searchDetailPlace: Place?
    @Published var searchResults: [Place] = []
    @Published var searchText = "" {
        didSet { if oldValue != searchText { resetSearchSession() } }
    }
    @Published private(set) var loadingMoreSearch = false
    @Published private(set) var searchHasMore = false
    @Published private(set) var searchPageError: String?
    @Published private(set) var searchPageRevision = UUID()
    @Published var searching = false
    @Published var loading = false
    @Published var saving = false
    @Published var errorMessage: String?
    @Published var routeError: String?
    @Published var routeSelectionRequest = UUID()
    @Published var routeCandidates: [DisplayRoute] = []
    @Published var routeCandidatePoint = CGPoint.zero
    @Published var displayRoutes: [DisplayRoute] = []
    @Published var routeProgress = ""
    @Published var camera: CameraCommand?
    @Published var locating = UUID()
    @Published private(set) var locationMode: LocationFollowMode = .idle
    func cycleLocationMode() { locationMode = locationMode.next; locating = UUID() }
    func stopLocationFollowing() { locationMode = .idle }
    @Published var mapViewportInsets: MapViewportInsets = .phone
    var bounds: SearchBounds?
    let demo: Bool
    private var routeTask: Task<Void, Never>?
    private var refreshGeneration = UUID()
    private var searchGeneration = UUID()
    private var searchTask: Task<PlaceSearchPage, Error>?
    private var activeSearch: (query: String, bounds: SearchBounds?, services: any MapServices, revision: UUID)?
    private var nextSearchRequest: PlaceSearchRequest?
    private var routeGeneration = UUID()
    private var connectionRevision = UUID()
    private var dataRevision = UUID()
    private var refreshing = false
    private var startupLocation: Coordinate?
    private var startupLocationFinished = false
    private var startupMapInteracted = false
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
    var mapMarkers: [Marker] {
        guard !placeSearchPresented, dayMapBrowsing, let day else { return markers }
        let ids = Set(day.markerIds + day.chains.flatMap { $0 })
        return markers.filter { ids.contains($0.id) }
    }
    func dayMapNumber(for id: String) -> Int? {
        guard dayMapBrowsing, let day else { return nil }
        return DayMapJourney.stops(day: day, markers: markers).firstIndex { $0.marker.id == id }.map { $0 + 1 }
    }
    var mapDisplayRoutes: [DisplayRoute] {
        guard dayMapBrowsing, let dayID else { return displayRoutes }
        return displayRoutes.filter { $0.dayID == dayID }
    }
    var visibleMarkers: [Marker] {
        guard tripID != nil else { return markers }
        let ids = Set(visibleDays.flatMap(\.markerIds) + (day == nil ? (trip?.markerIds ?? []) : [])); return markers.filter { ids.contains($0.id) }
    }
    init(settings: Settings, demo: Bool = ProcessInfo.processInfo.arguments.contains("--demo"), configurationSource: (any MapConfigurationSource)? = nil, services: (any MapServices)? = nil, markerRepository: MarkerRepository = MarkerRepository(), routeCache: RouteCache = RouteCache()) {
        self.routeCache = routeCache
        self.markerRepository = markerRepository
        self.settings = settings; self.demo = demo; self.servicesOverride = services; self.configurationSource = configurationSource ?? FixedMapConfigurationSource()
        if demo { loadDemo() }
    }
    func connect() async {
        applePOIRequest?.task.cancel(); applePOIRequest = nil; appleMapItems = [:]
        connectionRevision = UUID(); refreshGeneration = UUID(); dataRevision = UUID()
        loading = false; refreshing = false; saving = false
        failedSaveAction = nil; canResumeFailedSave = false; tripSaveRecovery = nil
        pendingCreatedMarkers = [:]; pendingCreatedTrips = [:]
        dayEditorDraft = nil; pendingCreatedDays = [:]
        endAddingPlace()
        endDayMapBrowsing()
        tripID = nil; dayID = nil; selectedMarker = nil; selectedSearchPlaceID = nil; addPlaceTripID = nil; addPlaceDay = nil; searchResults = []; markers = []; trips = []
        camera = nil; startupCameraPending = true
        resetSearchSession(); rebuildRoutes()
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
        applyStartupLocationFallback()
    }
    func refreshSelectedMarker(_ id: String) async {
        guard !demo, settings.configured, !saving else { return }
        let revision = connectionRevision, dataVersion = dataRevision, client = api
        do {
            guard let marker = try await markerRepository.detail(id, using: client) else { return }
            try Task.checkCancellation()
            guard revision == connectionRevision, dataVersion == dataRevision, !saving else { return }
            guard let index = markers.firstIndex(where: { $0.id == id }) else {
                guard trips.contains(where: { trip in
                    (trip.markerIds ?? []).contains(id) || trip.days.contains(where: { $0.markerIds.contains(id) || $0.chains.contains(where: { $0.contains(id) }) })
                }) else { return }
                markers.append(marker); rebuildRoutes(); return
            }
            guard markers[index] != marker else { return }
            let moved = markers[index].coordinates != marker.coordinates
            markers[index] = marker
            if selectedMarker?.id == id { selectedMarker = marker }
            if moved { rebuildRoutes() }
        } catch { /* Keep cached detail visible on background failure. */ }
    }
    func refreshAfterAIChange() async {
        // Serialize with an already-running refresh, then force a post-write snapshot.
        while refreshing || saving {
            do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        await refresh(force: true, quietly: true)
    }
    func runBackgroundUpdates() async {
        while !Task.isCancelled {
            await refresh(force: false, quietly: true)
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
        }
    }
    func receiveStartupLocation(_ coordinate: Coordinate) {
        guard coordinate.isValid, !startupLocationFinished else { return }
        startupLocation = coordinate
        applyStartupLocationFallback()
    }
    func noteMapInteraction() {
        startupMapInteracted = true; stopLocationFollowing()
        if dayMapBrowsing { dayMapCameraFollowing = false }
    }
    func noteDayMapTransform() { if dayMapBrowsing { dayMapCameraFollowing = false } }
    func beginDayMapBrowsing() {
        guard let day else { return }
        dayMapBrowsing = true; dayMapCameraFollowing = true
        dayMapFocusID = DayMapJourney.stops(day: day, markers: markers).first?.marker.id
        showWholeDayOnMap()
    }
    func endDayMapBrowsing() { dayMapBrowsing = false; dayMapFocusID = nil }
    func showWholeDayOnMap() {
        guard dayMapBrowsing, let day else { return }
        dayMapCameraFollowing = true
        let points = mapMarkers.filter { $0.coordinates.isValid }.map(\.coordinates)
            + mapDisplayRoutes.filter { $0.dayID == day.id }.flatMap(\.points)
        guard !points.isEmpty else { return }
        camera = CameraCommand(points: points, singlePointZoom: 15)
    }
    func focusDayMapMarker(_ id: String, moveCamera: Bool = true) {
        guard dayMapBrowsing, let marker = mapMarkers.first(where: { $0.id == id }) else { return }
        guard dayMapFocusID != id else { return }
        dayMapFocusID = id
        guard moveCamera, dayMapCameraFollowing, marker.coordinates.isValid else { return }
        camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 15)
    }
    func openDayMapPlaceDetails(_ id: String) {
        guard selectedMarker?.id != id, let marker = mapMarkers.first(where: { $0.id == id }) else { return }
        dayMapFocusID = id
        selectedMarker = marker
        camera = CameraCommand(points: [marker.coordinates], detailLayout: MarkerDetailLayout(marker: marker,
            itineraryCount: MarkerPresentation.itineraries(for: id, trips: trips).count, hasSelectedDay: day != nil))
    }
    private func applyStartupLocationFallback() {
        guard let location = startupLocation, !startupLocationFinished, !startupMapInteracted else { return }
        guard !startupCameraPending, camera == nil, draft == nil, selectedMarker == nil else { return }
        camera = CameraCommand(points: [location], singlePointZoom: 12)
        startupLocationFinished = true
    }
    func applyStartupCamera(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        guard startupCameraPending else { return }
        startupCameraPending = false
        // Do not interrupt a selection or camera action made while data was loading.
        guard tripID == nil, dayID == nil, selectedMarker == nil, draft == nil, camera == nil else { return }
        defer {
            applyStartupLocationFallback()
        }
        let today = StartupCamera.localDate(now: now, calendar: calendar)
        let orderedTrips = trips.sorted { $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate }
        for trip in orderedTrips {
            if let day = trip.days.filter({ $0.tripId == trip.id && $0.date == today }).sorted(by: { $0.id < $1.id }).first {
                select(trip: trip, day: day)
                return
            }
        }
        if let marker = StartupCamera.upcomingFirstMarker(trips: trips, markers: markers,
                                                          today: StartupCamera.localDate(now: now, calendar: calendar)) {
            camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 11)
        }
    }
    func perform(reserved: Bool = false, expectedRevision: UUID? = nil, onSuccess: (() -> Void)? = nil, _ operation: @escaping (APIClient) async throws -> Void) async -> Bool {
        guard expectedRevision == nil || expectedRevision == connectionRevision else { return false }
        guard !demo else { errorMessage = "当前为只读示例。配置服务后退出示例模式，即可保存到你的数据库。"; return false }
        guard reserved || !saving else { errorMessage = "请等待当前保存完成"; return false }
        // A background read must not block edits or overwrite their results.
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        saving = true; let revision = connectionRevision, client = api
        defer { if revision == connectionRevision { saving = false } }
        await markerRepository.invalidate(using: client)
        guard revision == connectionRevision else { return false }
        do {
            try await operation(client)
            guard revision == connectionRevision else { return false }
            onSuccess?()
            await markerRepository.invalidate(using: client)
            guard revision == connectionRevision else { return false }
            // The mutation has finished; refresh should not be blocked by saving.
            saving = false
            Task { await self.refresh(quietly: true) }
            return true
        } catch { if revision == connectionRevision { report(error) }; return false }
    }
    func deleteItinerary(tripID targetTripID: String, dayID targetDayID: String? = nil, deleteExclusiveMarkers: Bool, animated: Bool) {
        guard !demo else { errorMessage = "当前为只读示例，无法删除行程。"; return }
        guard !saving else { errorMessage = "请等待当前保存完成"; return }
        guard let ownerIndex = trips.firstIndex(where: { $0.id == targetTripID }) else { return }
        let owner = trips[ownerIndex]
        if let targetDayID {
            guard owner.days.count > 1 else { errorMessage = "行程至少保留一天"; return }
            guard owner.days.contains(where: { $0.id == targetDayID }) else { return }
        }
        let previousTrips = trips, previousMarkers = markers
        let revision = connectionRevision, client = api
        let removedDays = owner.days.filter { targetDayID == nil || $0.id == targetDayID }
        let candidates = Set(removedDays.flatMap { $0.markerIds + $0.chains.flatMap { $0 } } + (targetDayID == nil ? (owner.markerIds ?? []) : []))
        let allDays = trips.flatMap { $0.days }
        let exclusiveIDs = deleteExclusiveMarkers ? Set(candidates.filter { markerID in
            allDays.filter { $0.markerIds.contains(markerID) || $0.chains.contains(where: { $0.contains(markerID) }) }.count
                + trips.filter { ($0.markerIds ?? []).contains(markerID) }.count == 1
        }) : []
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        saving = true
        withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
            if let targetDayID {
                let remaining = owner.days.filter { $0.id != targetDayID }.sorted { $0.date < $1.date }
                let calendar = Calendar(identifier: .gregorian)
                trips[ownerIndex].days = remaining.enumerated().map { index, day in
                    var updated = day
                    updated.date = calendar.date(byAdding: .day, value: index, to: .fromDay(owner.startDate))!.dayString
                    return updated
                }
                trips[ownerIndex].endDate = trips[ownerIndex].days.last!.date
                if dayID == targetDayID { dayID = nil }
            } else {
                trips.remove(at: ownerIndex)
                if tripID == targetTripID { tripID = nil; dayID = nil }
            }
            markers.removeAll { exclusiveIDs.contains($0.id) }
            if let selectedMarker, exclusiveIDs.contains(selectedMarker.id) { self.selectedMarker = nil }
        }
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            await markerRepository.invalidate(using: client)
            do {
                if let targetDayID {
                    try await client.deleteDay(tripID: targetTripID, dayID: targetDayID, deleteExclusiveMarkers: deleteExclusiveMarkers)
                } else {
                    try await client.deleteTrip(id: targetTripID, deleteExclusiveMarkers: deleteExclusiveMarkers)
                }
                guard revision == connectionRevision else { return }
                await markerRepository.invalidate(using: client)
                guard revision == connectionRevision else { return }
                saving = false
                await refresh(quietly: true)
            } catch {
                guard revision == connectionRevision else { return }
                withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
                    trips = previousTrips; markers = previousMarkers
                }
                saving = false
                rebuildRoutes(preservingPlannedGeometry: true)
                report(error)
            }
        }
    }
    private func reserveEditorSave() -> Bool {
        guard !demo else { errorMessage = "当前为只读示例，无法保存。"; return false }
        guard !saving else { errorMessage = "请等待当前保存完成"; return false }
        saving = true
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        failedSaveAction = nil; canResumeFailedSave = false
        return true
    }
    private func retainFailedSave(_ action: @escaping () -> Void) {
        failedSaveAction = action; canResumeFailedSave = true
    }
    func resumeFailedSave() {
        let action = failedSaveAction
        failedSaveAction = nil; canResumeFailedSave = false; errorMessage = nil
        action?()
    }
    @discardableResult
    func saveMarkerInBackground(_ value: MarkerDraft, using client: APIClient? = nil) -> Bool {
        guard value.coordinates.isValid, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "请输入名称与有效坐标"; return false
        }
        guard reserveEditorSave() else { return false }
        let targetTripID = addPlaceTripID
        let target = value.marker == nil ? (addPlaceDay ?? day) : nil
        let previous = value.marker.flatMap { marker in markers.first { $0.id == marker.id } }
        if var optimistic = previous {
            optimistic.content.title = value.title; optimistic.content.iconType = value.icon
            optimistic.content.markdownContent = value.html; optimistic.content.headerImage = value.headerImage
            if let index = markers.firstIndex(where: { $0.id == optimistic.id }) { markers[index] = optimistic }
            if selectedMarker?.id == optimistic.id { selectedMarker = optimistic }
        }
        let revision = connectionRevision, requestClient = client ?? api
        if draft?.id == value.id { draft = nil }
        Task {
            let ok = await saveMarker(value, using: requestClient, reserved: true, target: target, expectedRevision: revision, targetTripID: targetTripID)
            guard revision == connectionRevision else { return }
            if !ok {
                if let previous {
                    if let index = markers.firstIndex(where: { $0.id == previous.id }) { markers[index] = previous }
                    if selectedMarker?.id == previous.id { selectedMarker = previous }
                }
                retainFailedSave { [weak self] in
                    self?.addPlaceDay = target
                    self?.addPlaceTripID = targetTripID
                    self?.draft = value
                }
            }
        }
        return true
    }
    @discardableResult
    func saveTripInBackground(_ value: TripSaveDraft, using suppliedClient: APIClient? = nil) -> Bool {
        guard !value.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入旅行名称"; return false }
        if value.trip == nil {
            guard !value.destinations.isEmpty, value.destinations.count <= 20,
                  value.destinations.allSatisfy(\.isValid),
                  Set(value.destinations.map(\.coordinateKey)).count == value.destinations.count else {
                errorMessage = "请搜索并选择目的地省市"; return false
            }
            guard value.start.dayString <= value.end.dayString else { errorMessage = "结束日期不能早于开始日期"; return false }
            guard TripDateRange(savedStart: value.start, savedEnd: value.end).isValid else {
                errorMessage = "一次最多创建 367 天，请缩短日期范围"; return false
            }
        }
        let previous = value.trip.flatMap { trip in trips.first { $0.id == trip.id } }
        var optimistic: Trip?
        if let trip = value.trip {
            guard let previous else { errorMessage = "旅行已不存在"; return false }
            do { optimistic = try previous.edited(name: value.name, emoji: value.emoji, start: value.start, end: value.end) }
            catch { errorMessage = error.localizedDescription; return false }
            guard previous.minimumEditableDayCount == trip.minimumEditableDayCount else {
                errorMessage = "行程天数已变化，请重新打开编辑"; return false
            }
        }
        guard reserveEditorSave() else { return false }
        let revision = connectionRevision, client = suppliedClient ?? api
        if let optimistic, let index = trips.firstIndex(where: { $0.id == optimistic.id }) { trips[index] = optimistic }
        Task {
            let ok = await perform(reserved: true, expectedRevision: revision) { _ in
                var body: [String: Any] = ["name": value.name, "startDate": value.start.dayString, "emoji": value.emoji]
                if let trip = value.trip {
                    let path = "trips/\(APIClient.id(trip.id))"
                    let latest: Trip = try await client.request(path)
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    _ = try latest.edited(name: value.name, emoji: value.emoji, start: value.start, end: value.end)
                    try await client.mutate(path, method: "PUT", body: body)
                    // Re-read after shifting: retries reuse days created before a partial failure.
                    let shifted: Trip = try await client.request(path)
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    var existing = Set(shifted.days.map(\.date))
                    var savedDays = shifted.days
                    var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(secondsFromGMT: 0)!
                    let count = TripDateRange(savedStart: value.start, savedEnd: value.end).dayCount
                    for index in 0..<count {
                        try Task.checkCancellation()
                        guard revision == self.connectionRevision else { throw CancellationError() }
                        let date = utc.date(byAdding: .day, value: index, to: value.start)!.dayString
                        if !existing.contains(date) {
                            let created: TripDay = try await client.request(path + "/days", method: "POST", body: ["date": date])
                            savedDays.append(created)
                            existing.insert(date)
                        }
                    }
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    try await client.mutate(path, method: "PUT", body: ["endDate": value.end.dayString])
                    if revision == self.connectionRevision, let index = self.trips.firstIndex(where: { $0.id == trip.id }) {
                        self.trips[index].days = savedDays.sorted { $0.date < $1.date }
                    }
                } else {
                    body["endDate"] = value.end.dayString
                    body["destinations"] = value.destinations.map(\.requestBody)
                    let created: Trip
                    if let pending = self.pendingCreatedTrips[value.id] {
                        created = pending
                        try await client.mutate("trips/\(APIClient.id(pending.id))", method: "PUT", body: body)
                    } else {
                        created = try await client.request("trips", method: "POST", body: body)
                        guard revision == self.connectionRevision else { throw CancellationError() }
                        self.pendingCreatedTrips[value.id] = created
                    }
                    if value.emoji != "✈️" { try await client.mutate("trips/\(APIClient.id(created.id))", method: "PUT", body: ["emoji": value.emoji]) }
                }
            }
            guard revision == connectionRevision else { return }
            if ok { pendingCreatedTrips[value.id] = nil }
            else {
                if let previous, let index = trips.firstIndex(where: { $0.id == previous.id }) { trips[index] = previous }
                retainFailedSave { [weak self] in self?.tripSaveRecovery = value }
            }
        }
        return true
    }
    @discardableResult
    func addSearchPlaceInBackground(_ place: Place, edited value: MarkerDraft, using suppliedClient: APIClient? = nil) -> Bool {
        guard placeSearchPresented, addingPlaceID == nil else { return false }
        guard value.coordinates.isValid, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let target = addPlaceDay, targetTripID = addPlaceTripID, session = addSession, revision = connectionRevision
        if let targetTripID, !trips.contains(where: { $0.id == targetTripID }) { errorMessage = "目标旅行已不存在"; return false }
        if let target, !trips.contains(where: { $0.id == target.tripId && $0.days.contains(where: { $0.id == target.id }) }) {
            errorMessage = "目标日期已不存在，请返回行程重新选择。"; return false
        }
        guard reserveEditorSave() else { return false }
        let client = suppliedClient ?? api
        // Preserve the selected marker ID and target day even if the search closes.
        var draft = value
        if let existing = savedMarker(for: place) { draft.marker = existing }
        let keyword = searchText, results = searchResults
        Task {
            let ok = await saveMarker(draft, using: client, reserved: true, target: target,
                expectedRevision: revision, openCreatedDetail: false, joinExistingTarget: true, targetTripID: targetTripID)
            guard revision == connectionRevision else { return }
            if ok {
                let marker = draft.marker.flatMap { existing in markers.first { $0.id == existing.id } }
                    ?? markers.first { $0.coordinates == draft.coordinates }
                if session == addSession {
                    if let marker { createdSearchMarkers[place.id] = marker }
                    addedPlaceIDs.insert(place.id)
                }
                rebuildRoutes(preservingPlannedGeometry: true)
            } else {
                if session == addSession { addPlaceError = errorMessage }
                retainFailedSave { [weak self] in
                    guard let self else { return }
                    if self.addSession != session {
                        self.beginAddingPlace(to: target, tripID: targetTripID)
                        self.searchText = keyword; self.searchResults = results
                    }
                    self.editingSearchPlaceID = place.id; self.draft = value
                }
            }
        }
        return true
    }
    func saveMarker(_ draft: MarkerDraft, using suppliedClient: APIClient? = nil, reserved: Bool = false, target: TripDay? = nil, expectedRevision: UUID? = nil, openCreatedDetail: Bool = true, joinExistingTarget: Bool = false, targetTripID: String? = nil) async -> Bool {
        let lookupRevision = connectionRevision
        let targetDay = draft.marker == nil || joinExistingTarget ? (reserved ? target : (addPlaceDay ?? day)) : nil
        let tripTarget = targetTripID ?? (reserved ? nil : addPlaceTripID)
        var resolvedAppleItem: MKMapItem?
        var draft = draft
        if let lookup = applePOIRequest, lookup.draftID == draft.id,
           lookup.coordinate == draft.coordinates, lookup.revision == connectionRevision,
           let item = await lookup.task.value, !lookup.task.isCancelled {
            resolvedAppleItem = item
            if #available(iOS 18.0, *), let id = item.identifier?.rawValue {
                draft.placeReferences = PlaceReferences(apple: PlaceReference(placeId: id))
            }
        }
        guard lookupRevision == connectionRevision else { return false }
        guard draft.coordinates.isValid, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入名称与有效坐标"; return false }
        let revision = expectedRevision ?? connectionRevision
        var createdMarker: Marker?
        var joinedDay: TripDay?
        let ok = await perform(reserved: reserved, expectedRevision: revision) { defaultClient in
            let client = suppliedClient ?? defaultClient
            if let marker = draft.marker {
                try await client.mutate("markers/\(APIClient.id(marker.id))", method: "PUT", body: ["title": draft.title, "iconType": draft.icon.rawValue, "markdownContent": draft.html, "headerImage": draft.headerImage])
            } else {
                let created: Marker
                if let pending = self.pendingCreatedMarkers[draft.id] {
                    created = pending
                    try await client.mutate("markers/\(APIClient.id(pending.id))", method: "PUT", body: ["title": draft.title, "iconType": draft.icon.rawValue, "markdownContent": draft.html, "headerImage": draft.headerImage])
                } else {
                    created = try await client.request("markers", method: "POST", body: ["coordinates": ["latitude": draft.coordinates.latitude, "longitude": draft.coordinates.longitude], "title": draft.title, "iconType": draft.icon.rawValue, "address": draft.address, "content": draft.html, "placeReferences": draft.placeReferences?.requestBody ?? [:]])
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    self.pendingCreatedMarkers[draft.id] = created
                }
                if !draft.headerImage.isEmpty { try await client.mutate("markers/\(APIClient.id(created.id))", method: "PUT", body: ["headerImage": draft.headerImage]) }
                createdMarker = created
            }
            guard revision == self.connectionRevision else { throw CancellationError() }
            if let targetDay, let marker = createdMarker ?? draft.marker {
                joinedDay = try await self.joinDefaultRoute(marker.id, day: targetDay, client: client, revision: revision)
            }
            if let tripTarget, let marker = createdMarker ?? draft.marker {
                try await client.mutate("trips/\(APIClient.id(tripTarget))/markers", method: "POST", body: ["markerId": marker.id])
            }
        }
        guard revision == connectionRevision else { return false }
        if ok {
            pendingCreatedMarkers[draft.id] = nil
            if let createdMarker, createdMarker.coordinates == draft.coordinates,
               createdMarker.placeReferences == draft.placeReferences, let resolvedAppleItem {
                appleMapItems[createdMarker.id] = (createdMarker.coordinates, createdMarker.placeReferences, resolvedAppleItem)
            }
            var saved = createdMarker ?? draft.marker
            if var updated = saved {
                updated.content.title = draft.title; updated.content.iconType = draft.icon
                updated.content.markdownContent = draft.html; updated.content.headerImage = draft.headerImage
                if draft.marker == nil { updated.content.address = draft.address }
                if let index = markers.firstIndex(where: { $0.id == updated.id }) { markers[index] = updated }
                else { markers.append(updated) }
                if selectedMarker?.id == updated.id { selectedMarker = updated }
                saved = updated
            }
            if let joinedDay, let ti = trips.firstIndex(where: { $0.id == joinedDay.tripId }),
               let di = trips[ti].days.firstIndex(where: { $0.id == joinedDay.id }) {
                // Refresh may already have supplied real visit IDs; don't replace it with a local draft.
                if !trips[ti].days[di].markerIds.contains(createdMarker?.id ?? draft.marker?.id ?? "") {
                    trips[ti].days[di] = joinedDay
                }
            }
            if let saved, let tripTarget, let ti = trips.firstIndex(where: { $0.id == tripTarget }),
               !(trips[ti].markerIds ?? []).contains(saved.id) { trips[ti].markerIds = (trips[ti].markerIds ?? []) + [saved.id] }
            if let saved, let targetDay, let ti = trips.firstIndex(where: { $0.id == targetDay.tripId }) {
                trips[ti].markerIds?.removeAll { $0 == saved.id }
            }
            if let saved, createdMarker != nil, openCreatedDetail, !placeSearchPresented,
               !reserved || (self.draft == nil && selectedMarker == nil) { focus(saved) }
            if self.draft?.id == draft.id { self.draft = nil }
        }
        return ok
    }
    @discardableResult
    func deleteMarker(_ marker: Marker, animated: Bool = true) -> Bool {
        guard !demo else { errorMessage = "当前为只读示例，无法删除地点。"; return false }
        guard !saving else { errorMessage = "请等待当前保存完成"; return false }
        guard markers.contains(where: { $0.id == marker.id }) else { return false }
        let previousMarkers = markers, previousTrips = trips
        let revision = connectionRevision, client = api
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        saving = true
        withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
            markers.removeAll { $0.id == marker.id }
            for ti in trips.indices {
                trips[ti].markerIds?.removeAll { $0 == marker.id }
                for di in trips[ti].days.indices {
                    trips[ti].days[di] = trips[ti].days[di].removing(marker.id)
                }
            }
            if selectedMarker?.id == marker.id { selectedMarker = nil }
        }
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            await markerRepository.invalidate(using: client)
            do {
                try await client.mutate("markers/\(APIClient.id(marker.id))", method: "DELETE")
                guard revision == connectionRevision else { return }
                await markerRepository.invalidate(using: client)
                guard revision == connectionRevision else { return }
                saving = false
                await refresh(quietly: true)
            } catch {
                guard revision == connectionRevision else { return }
                withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
                    markers = previousMarkers; trips = previousTrips
                }
                saving = false
                rebuildRoutes(preservingPlannedGeometry: true)
                report(error)
            }
        }
        return true
    }
    func updateDay(_ day: TripDay) async -> Bool {
        let body: [String: Any] = ["title": day.title ?? "", "emoji": day.emoji ?? "", "markerIds": day.markerIds, "chains": day.chains]
        return await perform { try await $0.mutate(Self.dayPath(day), method: "PUT", body: body) }
    }
    private var routeDropClickDeadline: Date = .distantPast
    var canActivateRouteRow: Bool { Date.now >= routeDropClickDeadline }
    func finishRouteDrop() { routeDropClickDeadline = .now.addingTimeInterval(0.35) }
    func saveRouteSchedule(_ request: RouteScheduleRequest, patch: [String: Any], using suppliedClient: APIClient? = nil) async -> Bool {
        guard let latest = trips.first(where: { $0.id == request.day.tripId })?.days.first(where: { $0.id == request.day.id }),
              latest.chains == request.day.chains,
              latest.routeChains?.contains(request.route) == true else {
            errorMessage = "路线已更新，请重新打开安排"; return false
        }
        let revision = connectionRevision
        return await perform(expectedRevision: revision) { client in
            let updated: TripDay = try await (suppliedClient ?? client).request(Self.dayPath(request.day) + "/chains/" + APIClient.id(request.route.id), method: "PATCH", body: patch)
            await self.acceptRouteSchedule(updated, revision: revision)
        }
    }
    private func acceptRouteSchedule(_ day: TripDay, revision: UUID) {
        guard revision == connectionRevision,
              let ti = trips.firstIndex(where: { $0.id == day.tripId }),
              let di = trips[ti].days.firstIndex(where: { $0.id == day.id }) else { return }
        let previous = trips[ti].days[di]
        trips[ti].days[di] = day
        let before = previous.chains.indices.map { previous.scheduledRoute(at: $0).map { route in route.stops.indices.dropLast().map { route.leg(at: $0)?.mode } } }
        let after = day.chains.indices.map { day.scheduledRoute(at: $0).map { route in route.stops.indices.dropLast().map { route.leg(at: $0)?.mode } } }
        if before != after { rebuildRoutes(preservingPlannedGeometry: true) }
    }
    static func dayPath(_ day: TripDay) -> String { "trips/\(APIClient.id(day.tripId))/days/\(APIClient.id(day.id))" }
    private func joinDefaultRoute(_ id: String, day: TripDay, client: APIClient, revision: UUID) async throws -> TripDay {
        guard revision == connectionRevision,
              let latest = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) else {
            throw AppError.message("目标日期已不存在")
        }
        let updated = latest.addingToDefaultRoute([id])
        if updated != latest {
            let write = try RouteOrderWrite(previous: latest, updated: updated)
            let confirmed: TripDay = try await client.request(write.path, method: write.method, body: write.body)
            guard revision == connectionRevision else { throw CancellationError() }
            return confirmed
        }
        guard revision == connectionRevision else { throw CancellationError() }
        return updated
    }
    @discardableResult func addMarker(_ marker: Marker, to day: TripDay) async -> Bool {
        addMarkerInBackground(marker, to: day)
    }
    @discardableResult
    func addMarkerInBackground(_ marker: Marker, to day: TripDay, using client: APIClient? = nil) -> Bool {
        guard var latest = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) else { return false }
        if latest.markerIds.contains(marker.id) { return true }
        latest = latest.addingToDefaultRoute([marker.id])
        return saveDayInBackground(latest, using: client)
    }
    @discardableResult
    func removeTripPlaceInBackground(_ markerID: String, from tripID: String) -> Bool {
        guard !demo, !saving, let ti = trips.firstIndex(where: { $0.id == tripID }),
              (trips[ti].markerIds ?? []).contains(markerID) else { return false }
        let previous = trips[ti].markerIds, revision = connectionRevision, client = api
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; saving = true
        withAnimation(AppMotion.listMutation(reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
            trips[ti].markerIds?.removeAll { $0 == markerID }
        }
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            await markerRepository.invalidate(using: client)
            do {
                try await client.mutate("trips/\(APIClient.id(tripID))/markers", method: "DELETE", body: ["markerId": markerID])
                guard revision == connectionRevision else { return }
                await markerRepository.invalidate(using: client)
                guard revision == connectionRevision else { return }
                saving = false; await refresh(quietly: true)
            } catch {
                guard revision == connectionRevision else { return }
                if let ti = trips.firstIndex(where: { $0.id == tripID }) { trips[ti].markerIds = previous }
                saving = false; rebuildRoutes(preservingPlannedGeometry: true); report(error)
            }
        }
        return true
    }
    func tripPlaces(_ trip: Trip) -> [Marker] {
        let ids = (trip.markerIds ?? []) + trip.days.sorted { $0.date < $1.date }
            .flatMap { $0.chains.flatMap { $0 } + $0.markerIds }
        let lookup = Dictionary(markers.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        return ids.compactMap { seen.insert($0).inserted ? lookup[$0] : nil }
    }

    func beginDayEditor(trip: Trip, day: TripDay? = nil) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let last = max(trip.endDate, trip.days.map(\.date).max() ?? trip.endDate)
        let date = day?.date ?? calendar.date(byAdding: .day, value: 1, to: .fromDay(last))!.dayString
        dayEditorDraft = DayEditorDraft(tripID: trip.id, day: day, date: date,
            title: day?.title ?? "", markerIDs: day?.markerIds ?? [])
    }

    @discardableResult
    func submitDayEditor(_ value: DayEditorDraft, using suppliedClient: APIClient? = nil) -> Bool {
        guard let ti = trips.firstIndex(where: { $0.id == value.tripID }) else { return false }
        let previous = trips[ti]
        // Existing references can outlive the loaded marker snapshot; validate only additions.
        let existingIDs = Set(value.day?.markerIds ?? [])
        let allowed = Set(tripPlaces(previous).map(\.id)).union(existingIDs)
        guard Set(value.markerIDs).isSubset(of: allowed) else {
            errorMessage = "地点已变化，请重新选择。"; return false
        }
        if let day = value.day, previous.days.first(where: { $0.id == day.id }) != day {
            errorMessage = "当天行程已更新，请重新打开编辑。"; return false
        }
        let createdBefore = pendingCreatedDays[value.id]
        if value.day == nil && createdBefore == nil && previous.days.contains(where: { $0.date == value.date }) {
            errorMessage = "该日期已存在，请重新添加。"; return false
        }
        guard TripDateRange(savedStart: .fromDay(previous.startDate), savedEnd: .fromDay(max(previous.endDate, value.date))).isValid else {
            errorMessage = "一次最多安排 367 天"; return false
        }
        let selected = value.markerIDs.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        var updated = value.day ?? createdBefore ?? TripDay(id: "pending-day-" + value.id.uuidString,
            tripId: value.tripID, date: value.date, markerIds: [], chains: [])
        if value.day != nil {
            for id in updated.markerIds where !selected.contains(id) { updated = updated.removing(id) }
            updated = updated.addingToDefaultRoute(selected)
        } else { updated.markerIds = selected }
        updated.title = value.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let write: RouteOrderWrite?
        do { write = try value.day.map { try RouteOrderWrite(previous: $0, updated: updated) } }
        catch { report(error); return false }
        guard reserveEditorSave() else { return false }
        let revision = connectionRevision, client = suppliedClient ?? api
        let pendingID = updated.id
        withAnimation(AppMotion.listMutation(reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
            trips[ti].days.removeAll { $0.id == pendingID }
            trips[ti].days.append(updated)
            trips[ti].days.sort { $0.date < $1.date }
            trips[ti].endDate = max(previous.endDate, value.date)
        }
        dayEditorDraft = nil
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            var confirmedCreated = createdBefore
            let ok = await perform(reserved: true, expectedRevision: revision) { _ in
                let path = "trips/\(APIClient.id(value.tripID))"
                if let write {
                    let titleOnly = value.day?.markerIds == updated.markerIds && value.day?.chains == updated.chains
                    let confirmed: TripDay = try await client.request(write.path, method: write.method,
                        body: titleOnly ? ["title": updated.title ?? ""] : write.body)
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    self.acceptRouteSchedule(confirmed, revision: revision)
                } else {
                    let body: [String: Any] = ["date": value.date, "title": updated.title ?? "", "markerIds": selected]
                    let saved: TripDay
                    if let existing = confirmedCreated {
                        saved = try await client.request(path + "/days/" + APIClient.id(existing.id), method: "PUT", body: body)
                    } else {
                        saved = try await client.request(path + "/days", method: "POST", body: body)
                    }
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    confirmedCreated = saved
                    self.pendingCreatedDays[value.id] = saved
                    if let index = self.trips.firstIndex(where: { $0.id == value.tripID }) {
                        self.trips[index].days.removeAll { $0.id == pendingID || $0.id == saved.id }
                        self.trips[index].days.append(saved)
                    }
                    try await client.mutate(path, method: "PUT", body: ["endDate": max(previous.endDate, value.date)])
                }
            }
            guard revision == connectionRevision else { return }
            if ok { pendingCreatedDays[value.id] = nil }
            else {
                if let index = trips.firstIndex(where: { $0.id == value.tripID }) {
                    trips[index] = previous
                    // A successful POST cannot be rolled back locally as if it never happened.
                    if let created = confirmedCreated {
                        trips[index].days.removeAll { $0.id == created.id }
                        trips[index].days.append(created)
                    }
                }
                retainFailedSave { [weak self] in self?.dayEditorDraft = value }
            }
            rebuildRoutes(preservingPlannedGeometry: true)
        }
        return true
    }

    @discardableResult
    func saveDayInBackground(_ day: TripDay, animated: Bool = true, using suppliedClient: APIClient? = nil) -> Bool {
        guard let previous = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) else { return false }
        let write: RouteOrderWrite
        do { write = try RouteOrderWrite(previous: previous, updated: day) }
        catch { report(error); return false }
        let revision = connectionRevision
        return persistDayInBackground(day, animated: animated, using: suppliedClient) { client in
            let confirmed: TripDay = try await client.request(write.path, method: write.method, body: write.body)
            await self.acceptRouteSchedule(confirmed, revision: revision)
        }
    }
    private func persistDayInBackground(_ day: TripDay, animated: Bool, using suppliedClient: APIClient? = nil, operation: @escaping (APIClient) async throws -> Void) -> Bool {
        guard !demo else { errorMessage = "当前为只读示例，无法保存。"; return false }
        guard !saving else { errorMessage = "请等待当前保存完成"; return false }
        guard let ti = trips.firstIndex(where: { $0.id == day.tripId }),
              let di = trips[ti].days.firstIndex(where: { $0.id == day.id }) else { return false }
        let previousTripMarkers = trips[ti].markerIds
        let previous = trips[ti].days[di], revision = connectionRevision, client = suppliedClient ?? api
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; loading = false
        saving = true
        withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
            trips[ti].days[di] = day
            trips[ti].markerIds?.removeAll { day.markerIds.contains($0) }
        }
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            await markerRepository.invalidate(using: client)
            do {
                try await operation(client)
                guard revision == connectionRevision else { return }
                await markerRepository.invalidate(using: client)
                guard revision == connectionRevision else { return }
                saving = false
                await refresh(quietly: true)
            } catch {
                guard revision == connectionRevision else { return }
                if let ti = trips.firstIndex(where: { $0.id == day.tripId }),
                   let di = trips[ti].days.firstIndex(where: { $0.id == day.id }) {
                    withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
                        trips[ti].days[di] = previous
                        trips[ti].markerIds = previousTripMarkers
                    }
                }
                saving = false
                rebuildRoutes(preservingPlannedGeometry: true)
                report(error)
            }
        }
        return true
    }
    /// Reuse saved places. Write the destination first so a failed move never loses the source.
    @discardableResult
    func transferDayPlaces(_ ids: Set<String>, from source: TripDay, to destination: TripDay,
                           copy: Bool, using suppliedClient: APIClient? = nil) -> Bool {
        guard !demo || suppliedClient != nil else { errorMessage = "当前为只读示例，无法保存。"; return false }
        guard !saving, source.tripId == destination.tripId, source.id != destination.id,
              let ti = trips.firstIndex(where: { $0.id == source.tripId }),
              let si = trips[ti].days.firstIndex(where: { $0.id == source.id }),
              let di = trips[ti].days.firstIndex(where: { $0.id == destination.id }) else { return false }
        let originalSource = trips[ti].days[si], originalDestination = trips[ti].days[di]
        guard originalSource == source, originalDestination == destination else {
            errorMessage = "行程已更新，请重新选择地点。"; return false
        }
        let ordered = originalSource.markerIds.filter { ids.contains($0) }
        guard !ordered.isEmpty else { return false }
        let updatedDestination = originalDestination.addingToDefaultRoute(ordered)
        let updatedSource = copy ? originalSource : ordered.reduce(originalSource) { $0.removing($1) }
        let destinationWrite: RouteOrderWrite, sourceWrite: RouteOrderWrite
        do {
            destinationWrite = try RouteOrderWrite(previous: originalDestination, updated: updatedDestination)
            sourceWrite = try RouteOrderWrite(previous: originalSource, updated: updatedSource)
        } catch { report(error); return false }
        let revision = connectionRevision, client = suppliedClient ?? api
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false; saving = true
        withAnimation(AppMotion.listMutation(reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
            trips[ti].days[si] = updatedSource; trips[ti].days[di] = updatedDestination
        }
        rebuildRoutes(preservingPlannedGeometry: true)
        Task {
            await markerRepository.invalidate(using: client)
            guard revision == connectionRevision else { return }
            var destinationWritten = false
            var compensationFailed = false
            do {
                if updatedDestination != originalDestination {
                    let confirmed: TripDay = try await client.request(destinationWrite.path, method: destinationWrite.method, body: destinationWrite.body)
                    guard revision == connectionRevision else { return }
                    acceptRouteSchedule(confirmed, revision: revision)
                    destinationWritten = true
                }
                guard revision == connectionRevision else { return }
                if !copy {
                    let confirmed: TripDay = try await client.request(sourceWrite.path, method: sourceWrite.method, body: sourceWrite.body)
                    guard revision == connectionRevision else { return }
                    acceptRouteSchedule(confirmed, revision: revision)
                }
                guard revision == connectionRevision else { return }
                await markerRepository.invalidate(using: client)
                guard revision == connectionRevision else { return }
                saving = false; await refresh(quietly: true)
            } catch {
                guard revision == connectionRevision else { return }
                if !copy {
                    // There is no cross-day transaction API; check the source before compensating.
                    do {
                        let serverSource: TripDay = try await client.request(Self.dayPath(originalSource))
                        guard revision == connectionRevision else { return }
                        if ordered.allSatisfy({ !serverSource.markerIds.contains($0) }) {
                            // A lost response can follow a successful write; don't undo a completed move.
                            acceptRouteSchedule(serverSource, revision: revision)
                            saving = false; await refresh(quietly: true); return
                        }
                        guard ordered.allSatisfy({ serverSource.markerIds.contains($0) }) else {
                            throw AppError.message("源日期的地点已发生变化")
                        }
                        if destinationWritten {
                            let confirmed: TripDay = try await client.request(Self.dayPath(originalDestination), method: "PUT", body: [
                                "markerIds": originalDestination.markerIds, "chains": originalDestination.chains])
                            guard revision == connectionRevision else { return }
                            acceptRouteSchedule(confirmed, revision: revision)
                        }
                    } catch { compensationFailed = true }
                }
                guard revision == connectionRevision else { return }
                if let ti = trips.firstIndex(where: { $0.id == source.tripId }) {
                    if let si = trips[ti].days.firstIndex(where: { $0.id == source.id }) { trips[ti].days[si] = originalSource }
                    if let di = trips[ti].days.firstIndex(where: { $0.id == destination.id }) {
                        trips[ti].days[di] = compensationFailed ? updatedDestination : originalDestination
                    }
                }
                saving = false; rebuildRoutes(preservingPlannedGeometry: true)
                if compensationFailed {
                    errorMessage = "移动未完成，目标日期可能已保留副本，请检查两天的行程。"
                    await refresh(quietly: true)
                } else { report(error) }
            }
        }
        return true
    }
    @discardableResult
    func removeDayPlacesInBackground(_ ids: Set<String>, from day: TripDay) -> Bool {
        guard let latest = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }),
              latest == day else { errorMessage = "行程已更新，请重新选择地点。"; return false }
        return saveDayInBackground(ids.reduce(latest) { $0.removing($1) })
    }
    func removeMarker(_ markerID: String, from day: TripDay, animated: Bool = true) async {
        guard var latest = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) else { return }
        latest = latest.removing(markerID)
        _ = persistDayInBackground(latest, animated: animated) {
            try await $0.mutate(Self.dayPath(day) + "/markers", method: "DELETE", body: ["markerId": markerID])
        }
    }
    @discardableResult
    func deleteDay(_ day: TripDay, deleteExclusiveMarkers: Bool = false, animated: Bool = true) async -> Bool {
        guard let owner = trips.first(where: { $0.id == day.tripId }), owner.days.count > 1 else {
            errorMessage = "行程至少保留一天"; return false
        }
        return await perform(onSuccess: { [self] in
            guard let index = trips.firstIndex(where: { $0.id == day.tripId }) else { return }
            withAnimation(AppMotion.listMutation(reduceMotion: !animated || UIAccessibility.isReduceMotionEnabled)) {
                trips[index].days.removeAll { $0.id == day.id }
                if dayID == day.id { dayID = nil }
            }
            rebuildRoutes(preservingPlannedGeometry: true)
        }) { try await $0.deleteDay(tripID: day.tripId, dayID: day.id, deleteExclusiveMarkers: deleteExclusiveMarkers) }
    }
    func select(trip: Trip?, day: TripDay? = nil, focus: Bool = true) {
        if tripID != trip?.id || dayID != day?.id {
            dayMapFocusID = nil; dayMapCameraFollowing = true
        }
        if day == nil { endDayMapBrowsing() }
        tripID = trip?.id; dayID = day?.id; selectedMarker = nil
        rebuildRoutes(preservingPlannedGeometry: true)
        guard focus else { return }
        if let day {
            let ids = Set(day.markerIds + day.chains.flatMap { $0 })
            let points = markers.filter { ids.contains($0.id) && $0.coordinates.isValid }.map(\.coordinates)
            if !points.isEmpty { camera = CameraCommand(points: points, singlePointZoom: 15) }
        } else if let trip {
            let ids = Set((trip.markerIds ?? []) + trip.days.flatMap { $0.markerIds + $0.chains.flatMap { $0 } })
            let points = markers.filter { ids.contains($0.id) && $0.coordinates.isValid }.map(\.coordinates)
            if !points.isEmpty { camera = CameraCommand(points: points, singlePointZoom: 12) }
        } else {
            fly(visibleMarkers.filter { $0.coordinates.isValid }.map(\.coordinates))
        }
    }
    func routeDayLabel(_ route: DisplayRoute) -> String {
        guard let trip = trips.first(where: { $0.id == route.tripID }),
              let index = trip.days.sorted(by: { $0.date < $1.date }).firstIndex(where: { $0.id == route.dayID }) else { return "当天" }
        return "第\(index + 1)天"
    }
    func offerRoutes(_ routes: [DisplayRoute], at point: CGPoint) {
        guard !placeSearchPresented else { return }
        routeCandidatePoint = point
        routeCandidates = routes.sorted { a, b in
            if a.tripID != b.tripID { return a.tripID < b.tripID }
            let days = trips.first(where: { $0.id == a.tripID })?.days ?? []
            return (days.first { $0.id == a.dayID }?.date ?? "") < (days.first { $0.id == b.dayID }?.date ?? "")
        }
    }
    func selectRoute(_ route: DisplayRoute) {
        guard let trip = trips.first(where: { $0.id == route.tripID }), let day = trip.days.first(where: { $0.id == route.dayID }) else { return }
        if tripID != trip.id || dayID != day.id { select(trip: trip, day: day, focus: false) }
        routeCandidates = []
        routeSelectionRequest = UUID()
    }
    func selectMapMarker(_ marker: Marker) {
        if dayMapBrowsing && !placeSearchPresented {
            focusDayMapMarker(marker.id, moveCamera: false)
            openDayMapPlaceDetails(marker.id)
        } else { focus(marker) }
    }
    func focus(_ marker: Marker) {
        if placeSearchPresented {
            guard draft == nil else { return }
            let place = Place(id: "saved-" + marker.id, name: marker.title, address: marker.content.address ?? "", coordinates: marker.coordinates, markerId: marker.id)
            if !searchResults.contains(where: { $0.id == place.id }) { searchResults.append(place) }
            choose(place, fromMap: true)
            return
        }
        if dayMapBrowsing { focusDayMapMarker(marker.id, moveCamera: false); return }
        guard selectedMarker?.id != marker.id else { return }
        let detail = MarkerDetailLayout(marker: marker,
            itineraryCount: MarkerPresentation.itineraries(for: marker.id, trips: trips).count,
            hasSelectedDay: day != nil)
        selectedMarker = marker
        camera = CameraCommand(points: [marker.coordinates], detailLayout: detail)
    }
    func fly(_ points: [Coordinate]) { if !points.isEmpty { camera = CameraCommand(points: points) } }
    func create(at coordinate: Coordinate, poiName: String? = nil, placeReferences: PlaceReferences? = nil) {
        guard coordinate.isValid, draft?.marker == nil, !saving else { return }
        if draft?.coordinates == coordinate { return }
        let selectedName = poiName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let searchSession = addSession, revision = connectionRevision
        var searchPlaceID: String?
        if placeSearchPresented {
            let place = Place(id: UUID().uuidString, name: selectedName.isEmpty ? "地图选点" : selectedName,
                              address: String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude),
                              coordinates: coordinate, placeReferences: placeReferences)
            searchResults.append(place); editingSearchPlaceID = place.id
            searchPlaceID = place.id
        }
        selectedSearchPlaceID = nil; draftExpanded = false
        var pending = draft ?? MarkerDraft(coordinates: coordinate)
        applePOIRequest?.task.cancel(); applePOIRequest = nil
        pending.placeReferences = placeReferences
        pending.coordinates = coordinate
        pending.title = selectedName
        pending.address = ""
        pending.placeLookupFailed = false
        pending.resolvingPlace = true
        draft = pending
        camera = CameraCommand(points: [coordinate], revealDraft: true)
        let draftID = pending.id
        Task {
            do {
                let place = try await mapServices.details(at: coordinate)
                if let searchPlaceID, searchSession == self.addSession, revision == self.connectionRevision,
                   let index = self.searchResults.firstIndex(where: { $0.id == searchPlaceID }) {
                    var result = place
                    result.id = searchPlaceID
                    result.coordinates = coordinate
                    result.name = selectedName.isEmpty ? place.name : selectedName
                    if result.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.name = self.searchResults[index].name
                    }
                    if result.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        result.address = self.searchResults[index].address
                    }
                    result.placeReferences = placeReferences ?? place.placeReferences
                    self.searchResults[index] = result
                }
                guard self.draft?.id == draftID, self.draft?.coordinates == coordinate else { return }
                if selectedName.isEmpty, self.draft?.title == pending.title {
                    self.draft?.title = place.name
                }
                if self.draft?.address == pending.address { self.draft?.address = place.address }
                self.draft?.resolvingPlace = false
            } catch {
                guard self.draft?.id == draftID, self.draft?.coordinates == coordinate else { return }
                self.draft?.resolvingPlace = false
                self.draft?.placeLookupFailed = true
            }
        }
    }
    func beginAddingPlace(to day: TripDay? = nil, tripID: String? = nil) {
        endAddingPlace()
        routeCandidates = []; selectedMarker = nil
        addPlaceDay = day
        addPlaceTripID = day == nil ? tripID : nil
        placeSearchPresented = true
        showNearbySearchPlaces()
    }
    func showNearbySearchPlaces() {
        guard placeSearchPresented, searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let center: Coordinate?
        if let bounds {
            center = Coordinate(latitude: (bounds.south + bounds.north) / 2, longitude: (bounds.west + bounds.east) / 2)
        } else { center = camera?.points.first ?? markers.first(where: { $0.coordinates.isValid })?.coordinates }
        guard let center, center.isValid else { searchResults = []; return }
        searchResults = markers.filter { $0.coordinates.isValid && Coordinates.distance(center, $0.coordinates) <= 30_000 }
            .sorted { Coordinates.distance(center, $0.coordinates) < Coordinates.distance(center, $1.coordinates) }
            .map { Place(id: "saved-" + $0.id, name: $0.title, address: $0.content.address ?? "",
                         coordinates: $0.coordinates, markerId: $0.id) }
    }
    func endAddingPlace() {
        searchDetailPlace = nil
        addSession = UUID(); addedPlaceIDs = []; createdSearchMarkers = [:]
        addPlaceError = nil; editingSearchPlaceID = nil
        draft = nil
        addPlaceTripID = nil; addPlaceDay = nil; placeSearchPresented = false
        clearSearch()
    }
    func search() async {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { clearSearch(); return }
        resetSearchSession()
        // Freeze the bounds for this search. Camera focus or selection must not
        // change page two's search area, nor reset already loaded results.
        activeSearch = (query, bounds?.expanded(factor: 2), mapServices, connectionRevision)
        searchResults = PlaceSearchMerger.merge(query: query, markers: markers, places: [])
        await fetchSearchPage(PlaceSearchRequest(), first: true)
    }
    func loadMoreSearch() async {
        guard !searching, !loadingMoreSearch, draft == nil, let request = nextSearchRequest else { return }
        await fetchSearchPage(request, first: false)
    }
    private func fetchSearchPage(_ request: PlaceSearchRequest, first: Bool) async {
        guard let context = activeSearch else { return }
        let generation = searchGeneration
        if first { searching = true } else { loadingMoreSearch = true }
        searchPageError = nil
        let mockPlaces: [Place]?
        if demo && servicesOverride == nil {
            if ProcessInfo.processInfo.arguments.contains("--search-visual-demo") {
                let names = ["梧桐咖啡 · 街角店", "沿街咖啡", "白昼咖啡与面包", "巷里咖啡工作室", "慢行咖啡 · 花园店", "木窗咖啡", "河岸咖啡", "晴日咖啡馆", "转角咖啡与书", "午后咖啡", "小庭院咖啡", "街区咖啡"]
                let streets = ["武康路", "安福路", "乌鲁木齐中路", "愚园路"]
                mockPlaces = names.enumerated().map { i, name in
                    Place(id: "visual-\(i)", name: name, address: "上海市 · \(streets[i % streets.count]) \(20 + i * 13)号（示例）",
                        coordinates: Coordinate(latitude: 31.215 + Double(i) * 0.001, longitude: 121.44 + Double(i) * 0.0004),
                        types: ["餐饮服务", "咖啡厅"])
                }
            } else if ProcessInfo.processInfo.arguments.contains("--paged-search-demo") {
                mockPlaces = (0..<45).map { i in
                    Place(id: "paged-\(i)", name: "\(context.query) \(i + 1)", address: "上海市",
                          coordinates: Coordinate(latitude: 31.2 + Double(i) * 0.0001, longitude: 121.4))
                }
            } else {
                mockPlaces = markers.filter { $0.title.localizedCaseInsensitiveContains(context.query) }.map {
                    Place(id: $0.id, name: $0.title, address: $0.content.address ?? "", coordinates: $0.coordinates)
                }
            }
        } else { mockPlaces = nil }
        let task = Task<PlaceSearchPage, Error> {
            if let mockPlaces {
                let start = min(mockPlaces.count, (request.page - 1) * request.pageSize)
                let end = min(mockPlaces.count, start + request.pageSize)
                return PlaceSearchPage(places: Array(mockPlaces[start..<end]), page: request.page, pageSize: request.pageSize,
                                       nextPage: end < mockPlaces.count ? request.page + 1 : nil)
            }
            return try await context.services.searchPage(context.query, bounds: context.bounds, request: request)
        }
        searchTask = task
        defer {
            if searchGeneration == generation { searching = false; loadingMoreSearch = false; searchTask = nil }
        }
        do {
            let page = try await task.value
            guard !Task.isCancelled, !task.isCancelled, searchGeneration == generation,
                  connectionRevision == context.revision else { return }
            // Across-page duplicates don't create repeated list/map identities.
            searchResults = PlaceSearchMerger.merge(query: context.query, markers: markers, places: searchResults + page.places)
            if let next = page.nextPage, next > request.page {
                nextSearchRequest = PlaceSearchRequest(page: next, pageSize: page.pageSize, pageToken: page.nextPageToken)
            } else { nextSearchRequest = nil }
            searchHasMore = nextSearchRequest != nil
            searchPageRevision = UUID()

        } catch {
            guard searchGeneration == generation, !task.isCancelled, !(error is CancellationError) else { return }
            if first { searchError = error.localizedDescription }
            else { searchPageError = "加载更多失败，点击重试" }
        }
    }
    private func resetSearchSession() {
        searchTask?.cancel(); searchTask = nil
        searchGeneration = UUID(); activeSearch = nil; nextSearchRequest = nil
        searching = false; loadingMoreSearch = false; searchHasMore = false; searchPageError = nil; searchError = nil
        searchResults = []; selectedSearchPlaceID = nil; searchPageRevision = UUID()
    }
    func clearSearch() { resetSearchSession(); searchText = ""; showNearbySearchPlaces() }
    func choose(_ place: Place, fromMap: Bool = false) {
        guard place.coordinates.isValid else { return }
        if placeSearchPresented {
            guard draft == nil else { return }
            if selectedSearchPlaceID != place.id {
                selectedSearchPlaceID = place.id; addPlaceError = nil
                fly([place.coordinates])
            }
            if fromMap {
                withAnimation(AppMotion.crossfade(reduceMotion: UIAccessibility.isReduceMotionEnabled)) {
                    searchDetailPlace = place
                }
            }
            return
        }
        if fromMap, selectedSearchPlaceID == place.id, draft != nil {
            draftExpanded = true
            return
        }
        selectedSearchPlaceID = place.id; draftExpanded = false
        fly([place.coordinates])
        draft = MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address, placeReferences: place.placeReferences)
    }
    var visibleSearchPlaces: [Place] { selectedSearchPlace.map { [$0] } ?? [] }
    var selectedSearchPlace: Place? { searchResults.first { $0.id == selectedSearchPlaceID } }
    func savedMarker(for place: Place) -> Marker? {
        // Provider POI IDs and our marker IDs are different namespaces.
        createdSearchMarkers[place.id] ?? markers.first {
            if let markerID = place.markerId { return $0.id == markerID }
            return $0.coordinates == place.coordinates
        }
    }
    func isPlaceAdded(_ place: Place) -> Bool {
        if addedPlaceIDs.contains(place.id) { return true }
        guard let marker = savedMarker(for: place) else { return false }
        guard let target = addPlaceDay else {
            guard let tripID = addPlaceTripID, let trip = trips.first(where: { $0.id == tripID }) else { return true }
            return (trip.markerIds ?? []).contains(marker.id) || trip.days.contains { $0.markerIds.contains(marker.id) }
        }
        let current = trips.first { $0.id == target.tripId }?.days.first { $0.id == target.id } ?? target
        return current.markerIds.contains(marker.id)
    }
    func prepareSearchPlaceAddition(_ place: Place) {
        guard draft == nil else { return }
        if savedMarker(for: place) != nil {
            Task { await activateSavedSearchPlace(place) }
            return
        }
        editingSearchPlaceID = place.id
        draft = savedMarker(for: place).map(MarkerDraft.init(marker:))
            ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address, placeReferences: place.placeReferences)
    }
    func activateSavedSearchPlace(_ place: Place) async {
        guard placeSearchPresented, draft == nil, let marker = savedMarker(for: place) else { return }
        if addPlaceDay != nil || addPlaceTripID != nil {
            choose(place)
            if !isPlaceAdded(place) { _ = await addSearchPlace(place) }
        } else {
            endAddingPlace()
            focus(marker)
        }
    }
    /// Keep the created ID after a partial failure so retry only completes membership.
    @discardableResult func addSearchPlace(_ place: Place, edited: MarkerDraft? = nil, using suppliedClient: APIClient? = nil, reserved: Bool = false) async -> Bool {
        defer { if reserved { saving = false } }
        guard placeSearchPresented, (reserved || !saving), addingPlaceID == nil else { return false }
        let target = addPlaceDay, targetTripID = addPlaceTripID
        if let targetTripID, !trips.contains(where: { $0.id == targetTripID }) { addPlaceError = "目标旅行已不存在"; return false }
        if let target, trips.first(where: { $0.id == target.tripId })?.days.contains(where: { $0.id == target.id }) != true {
            addPlaceError = "目标日期已不存在，请返回行程重新选择。"; return false
        }
        if edited == nil && isPlaceAdded(place) { return true }
        if tripPlacesPreview, target == nil, let tripID, suppliedClient == nil {
            let value = edited ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address, placeReferences: place.placeReferences)
            let marker = savedMarker(for: place) ?? Marker(id: "preview-" + place.id, coordinates: value.coordinates,
                content: MarkerContent(id: "preview-" + place.id, title: value.title, address: value.address,
                    iconType: value.icon, markdownContent: value.html))
            if !(previewTripPlaces[tripID] ?? []).contains(where: { $0.id == marker.id }) {
                previewTripPlaces[tripID, default: []].append(marker)
            }
            createdSearchMarkers[place.id] = marker
            addedPlaceIDs.insert(place.id)
            return true
        }
        guard !demo || suppliedClient != nil else {
            addPlaceError = "当前为只读示例，连接服务后可添加地点。"; return false
        }
        let value = edited ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address, placeReferences: place.placeReferences)
        guard value.coordinates.isValid, !value.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            addPlaceError = "请输入名称与有效坐标"; return false
        }
        let session = addSession, revision = connectionRevision, client = suppliedClient ?? api
        addingPlaceID = place.id; saving = true; addPlaceError = nil
        dataRevision = UUID(); refreshGeneration = UUID(); refreshing = false
        defer { addingPlaceID = nil; saving = false }
        do {
            var marker: Marker
            if let existing = savedMarker(for: place) { marker = existing }
            else {
                marker = try await client.request("markers", method: "POST", body: [
                    "coordinates": ["latitude": value.coordinates.latitude, "longitude": value.coordinates.longitude],
                    "title": value.title, "iconType": value.icon.rawValue, "address": value.address, "content": value.html, "placeReferences": value.placeReferences?.requestBody ?? [:]])
            }
            guard revision == connectionRevision, session == addSession else { return false }
            createdSearchMarkers[place.id] = marker
            if edited != nil {
                try await client.mutate("markers/\(APIClient.id(marker.id))", method: "PUT", body: [
                    "title": value.title, "iconType": value.icon.rawValue, "markdownContent": value.html, "headerImage": value.headerImage])
                guard revision == connectionRevision, session == addSession else { return false }
                marker.content.title = value.title; marker.content.iconType = value.icon
                marker.content.markdownContent = value.html; marker.content.headerImage = value.headerImage
                createdSearchMarkers[place.id] = marker
            }
            var joinedDay: TripDay?
            if let target, !isPlaceAdded(place) {
                joinedDay = try await joinDefaultRoute(marker.id, day: target, client: client, revision: revision)
            }
            if let targetTripID, !isPlaceAdded(place) {
                try await client.mutate("trips/\(APIClient.id(targetTripID))/markers", method: "POST", body: ["markerId": marker.id])
            }
            guard revision == connectionRevision, session == addSession else { return false }
            if let index = markers.firstIndex(where: { $0.id == marker.id }) { markers[index] = marker }
            else { markers.append(marker) }
            if let joinedDay, let ti = trips.firstIndex(where: { $0.id == joinedDay.tripId }),
               let di = trips[ti].days.firstIndex(where: { $0.id == joinedDay.id }) { trips[ti].days[di] = joinedDay }
            if let targetTripID, let ti = trips.firstIndex(where: { $0.id == targetTripID }),
               !(trips[ti].markerIds ?? []).contains(marker.id) {
                trips[ti].markerIds = (trips[ti].markerIds ?? []) + [marker.id]
            }
            if let target, let ti = trips.firstIndex(where: { $0.id == target.tripId }) {
                trips[ti].markerIds?.removeAll { $0 == marker.id }
            }
            addedPlaceIDs.insert(place.id); rebuildRoutes(preservingPlannedGeometry: true)
            await markerRepository.invalidate(using: client)
            return true
        } catch {
            guard revision == connectionRevision, session == addSession else { return false }
            addPlaceError = createdSearchMarkers[place.id] == nil ? error.localizedDescription : "地点已保存，后续操作未完成：" + error.localizedDescription
            return false
        }
    }
    func report(_ error: Error) { if error is CancellationError { return }; errorMessage = error.localizedDescription }
    func rebuildRoutes(preservingPlannedGeometry: Bool = false) {
        routeTask?.cancel(); let generation = UUID(); routeGeneration = generation
        // Capture immutable inputs before leaving the UI actor. Do not await API work
        // before committing navigation, and do not publish partially built route arrays.
        let days = visibleDays, snapshotMarkers = markers, selectedTrip = trip, previous = displayRoutes
        let planning = settings.planning && !demo
        let services = mapServices, provider = mapConfiguration.directionsProvider, server = settings.baseURL
        routeError = nil; routeProgress = ""
        routeTask = Task {
            defer { if self.routeGeneration == generation { routeProgress = "" } }
            #if DEBUG
            if demo, ProcessInfo.processInfo.arguments.contains("--delayed-route-build-preview") {
                do { try await Task.sleep(for: .seconds(8)) } catch { return }
            }
            #endif
            guard var segments = try? await routeProcessing.build(days: days, markers: snapshotMarkers,
                                                                  selectedTrip: selectedTrip, previous: previous,
                                                                  preserve: preservingPlannedGeometry && !planning, planning: planning),
                  !Task.isCancelled, self.routeGeneration == generation else { return }
            if planning {
                guard let restored = try? await routeProcessing.restoringCachedGeometry(segments, cache: routeCache,
                            provider: provider, server: server),
                      !Task.isCancelled, self.routeGeneration == generation else { return }
                segments = restored
            }
            var transaction = Transaction(); transaction.disablesAnimations = true
            var displays = segments.map(\.display)
            #if DEBUG
            if demo, ProcessInfo.processInfo.arguments.contains("--delayed-route-distance-preview") {
                displays = displays.map { route in
                    var copy = route; copy.isPlanned = true; copy.distance = 850; return copy
                }
            }
            #endif
            guard let presented = try? await routeProcessing.separatingOverlaps(displays),
                  !Task.isCancelled, self.routeGeneration == generation else { return }
            withTransaction(transaction) { displayRoutes = presented }
            guard planning, !segments.isEmpty else { return }
            var failed = 0, completed = 0
            for segment in segments {
                let display = segment.display, a = segment.origin, b = segment.destination
                guard !Task.isCancelled, self.routeGeneration == generation else { return }
                let key = RouteCache.key(a, b, mode: display.transportMode, provider: provider, server: server)
                do {
                    var route = await routeCache.get(key)
                    if route == nil {
                        route = try await services.route(a, b, mode: display.transportMode)
                        try Task.checkCancellation()
                        guard self.routeGeneration == generation else { return }
                        if let route { await routeCache.put(route, key: key) }
                        try await Task.sleep(for: .milliseconds(1200))
                    }
                    guard let route else { continue }
                    let points = try await routeProcessing.displayPoints(route, origin: a, destination: b)
                    guard !Task.isCancelled, self.routeGeneration == generation else { return }
                    if let index = displays.firstIndex(where: { $0.id == display.id }) {
                        var updated = displays[index]
                        let distance = route.distance
                        if updated.points != points || updated.isPlanned != !route.isFallback || updated.distance != distance || updated.isDashed != route.isFallback {
                            updated.points = points; updated.isPlanned = !route.isFallback
                            updated.distance = distance
                            updated.isDashed = route.isFallback
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            displays[index] = updated
                            let presented = try await routeProcessing.separatingOverlaps(displays)
                            guard !Task.isCancelled, self.routeGeneration == generation else { return }
                            withTransaction(transaction) { displayRoutes = presented }
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
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--cover-resize-preview") {
            markers[2].content.headerImage = "https://example.invalid/cover.jpg"
        }
        if ProcessInfo.processInfo.arguments.contains("--long-note-preview") {
            markers[1].content.markdownContent = (1...24).map { "<p>第\($0)段旅行笔记：查看地点信息与当天安排。</p>" }.joined() + "<p>长笔记结束</p>"
        }
        #endif
        let days = [TripDay(id: "day-1", tripId: "demo-trip", date: "2026-10-01", title: "梧桐街区漫步", colorIndex: 0, markerIds: ["demo-0","demo-1","demo-2"], chains: [["demo-0","demo-1","demo-2"]]),
                    TripDay(id: "day-2", tripId: "demo-trip", date: "2026-10-02", title: "城市与旧时光", colorIndex: 1, markerIds: ["demo-2","demo-3","demo-4"], chains: [["demo-2","demo-3","demo-4"]])]
        trips = [Trip(id: "demo-trip", name: "上海 · 秋日散步", description: "示例行程", startDate: "2026-10-01", endDate: "2026-10-02", emoji: "🍂", days: days)]
        if tripPlacesPreview {
            previewTripPlaces["demo-trip"] = [
                Marker(id: "preview-cafe", coordinates: Coordinate(latitude: 31.211, longitude: 121.434), content: MarkerContent(id: "preview-cafe", title: "街角咖啡馆", address: "上海市徐汇区 · 武康路", iconType: .food, markdownContent: "")),
                Marker(id: "preview-bookshop", coordinates: Coordinate(latitude: 31.216, longitude: 121.442), content: MarkerContent(id: "preview-bookshop", title: "梧桐下的书店", address: "上海市静安区 · 安福路", iconType: .landmark, markdownContent: ""))
            ]
        }

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--day-stale-member-preview") {
            trips[0].days[0].markerIds.insert("deleted-marker", at: 0)
        }
        if ProcessInfo.processInfo.arguments.contains("--transport-schedule-preview") {
            let stops = [ChainStop(id: "preview-stop-0", markerId: "demo-0", startTime: "09:30", durationMinutes: 60),
                         ChainStop(id: "preview-stop-1", markerId: "demo-1", startTime: "10:45", durationMinutes: 45),
                         ChainStop(id: "preview-stop-2", markerId: "demo-2")]
            trips[0].days[0].routeChains = [RouteChain(id: "preview-route", stops: stops,
                legs: [ChainLeg(fromStopId: stops[0].id, toStopId: stops[1].id, mode: .subway,
                    serviceNumber: "10号线", startTime: "10:30", durationMinutes: 15, note: "陕西南路站 · 往虹桥火车站方向")])]
            if ProcessInfo.processInfo.arguments.contains("--isolated-transport-drag-preview") {
                trips[0].days[0].markerIds.append("demo-3")
            }

        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--inline-address-preview") {
            for index in markers.indices {
                markers[index].content.address = "上海市徐汇区淮海中路与武康路交叉口，历史文化风貌街区入口旁，沿街步行至建筑南侧入口"
            }
        }
        if ProcessInfo.processInfo.arguments.contains("--day-detail-style-preview") {
            // Read-only typography fixture for notes, long names, and the untitled header.
            trips[0].days[0].markerIds.append("demo-3")
            trips[0].days[0].routeChains?[0].stops[0].note = "沿街散步，看看老建筑。"
            if ProcessInfo.processInfo.arguments.contains("--day-detail-long-preview") {
                markers[0].content.title = "武康大楼与衡复历史文化风貌区漫步"
                trips[0].days[0].title = nil
                trips[0].days[0].routeChains?[0].stops[0].note = "先到沿街入口集合，参观前核对预约时间；雨天从侧门进入，沿着连廊前往展厅。"
            }
        }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--day-chain-layout-preview") {
            markers[0].content.title = "武康大楼与衡复历史文化风貌区的老建筑和街巷漫步路线起点"
            markers[0].content.headerImage = "http://localhost:8766/tokyo.jpg"
            markers[3].content.title = "静安寺与南京西路历史街区的最后一站和返程集合地点"
            trips[0].days[0].routeChains?[0].legs[0].note = String(repeating: "陕西南路站上车，往虹桥火车站方向；提前确认站台，保管好随身行李。", count: 8)
        }
        if ProcessInfo.processInfo.arguments.contains("--journey-card-style-preview") {
            // Read-only fixture; photos come from the developer's local preview server.
            markers[0].content.headerImage = "http://localhost:8766/tokyo.jpg"
            markers[3].content.headerImage = "http://localhost:8766/street.jpg"
            trips[0].days[1].title = nil
            let summaryIDs = ["demo-2", "demo-3", "demo-4", "demo-0", "demo-1"]
            let summaryStops = summaryIDs.enumerated().map { index, id in
                ChainStop(id: "summary-stop-\(index)", markerId: id,
                    startTime: index == 1 ? "10:30" : index == 2 ? "12:00" : nil)
            }
            trips[0].days[1].markerIds = summaryIDs
            trips[0].days[1].chains = [summaryIDs]
            trips[0].days[1].routeChains = [RouteChain(id: "summary-route", stops: summaryStops,
                legs: [TransportMode.cycling, .walking, .bus, .subway].enumerated().map { index, mode in
                    ChainLeg(fromStopId: summaryStops[index].id, toStopId: summaryStops[index + 1].id, mode: mode)
                })]
            trips[0].days.append(TripDay(id: "day-3", tripId: "demo-trip", date: "2026-10-03",
                title: nil, markerIds: ["demo-1", "demo-4"], chains: []))
            trips[0].days.append(TripDay(id: "day-4", tripId: "demo-trip", date: "2026-10-04", markerIds: [], chains: []))
            trips[0].endDate = "2026-10-04"
            trips.append(Trip(id: "style-trip-2", name: "冬日 · 城市漫游", startDate: "2026-12-12", endDate: "2026-12-14", emoji: "❄️", days: []))
            trips.append(Trip(id: "style-trip-3", name: "周末小旅行", startDate: "2026-09-12", endDate: "2026-09-13", emoji: "🌿", days: [], markerIds: ["demo-3"]))
        }
        #endif
        if ProcessInfo.processInfo.arguments.contains("--overlapping-routes-demo") {
            trips[0].days[1].markerIds = ["demo-0", "demo-1", "demo-2"]
            trips[0].days[1].chains = [["demo-0", "demo-1", "demo-2"]]
        }
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
        if ProcessInfo.processInfo.arguments.contains("--ongoing-archive-preview") {
            let today = Date.fromDay(Date.now.dayString)
            trips = [("ongoing-new", -1, 7), ("ongoing-old", -3, 5),
                     ("upcoming", 20, 22), ("completed", -30, -28)].map { id, start, end in
                Trip(id: id, name: id == "ongoing-new" ? "京都漫游" : id == "ongoing-old" ? "关西之旅" : "示例旅途",
                     startDate: Calendar.current.date(byAdding: .day, value: start, to: today)!.dayString,
                     endDate: Calendar.current.date(byAdding: .day, value: end, to: today)!.dayString, days: [])
            }
            tripID = nil; dayID = nil
        }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--year-archive-preview") {
            trips += [("year-2025-a", "2025-11-02", "京都 · 秋色"),
                      ("year-2025-b", "2025-05-10", "海边的周末"),
                      ("year-2024", "2024-08-20", "山间散步"),
                      ("year-2023", "2023-03-14", "春日出发")].map { id, date, name in
                Trip(id: id, name: name, startDate: date, endDate: date, emoji: "🌿", days: [])
            }
        }
        #endif
        rebuildRoutes(); fly(markers.map(\.coordinates))
    }
}
struct CameraCommand: Identifiable {
    var id = UUID()
    var points: [Coordinate]
    var singlePointZoom: Double = 15
    var detailLayout: MarkerDetailLayout? = nil
    var revealDraft = false
    var bottomSheetFraction: Double? = nil
    var bottomSheetHeight: Double? = nil
    func viewportInsets(base: MapViewportInsets, height: Double, bottomSafeArea: Double,
                        bottomSheet: Bool) -> MapViewportInsets {
        var insets = base
        if let bottomSheetFraction {
            insets = MapViewportInsets(top: 80, left: 25, bottom: height * min(0.5, bottomSheetFraction) + bottomSafeArea + 25, right: 25)
        }
        if let bottomSheetHeight {
            insets = MapViewportInsets(top: 80, left: 25, bottom: min(bottomSheetHeight, height * 0.5) + bottomSafeArea + 25, right: 25)
        }
        if bottomSheet, revealDraft { insets.bottom = height * 0.5 + bottomSafeArea + 25 }
        if bottomSheet, let detailLayout {
            // The journey panel collapses when details open; its previous full height must not shift the camera.
            insets.bottom = detailLayout.occlusion(height: height, bottomSafeArea: bottomSafeArea) + 25
        }
        // Keep a visible region without truncating a half-height or taller detail sheet.
        insets.bottom = min(insets.bottom, max(0, height - insets.top - 80))
        return insets
    }
    // Single places always use an absolute level, never the previous map scale.
    var zoomLevel: Double? { points.count == 1 ? singlePointZoom : nil }
}
