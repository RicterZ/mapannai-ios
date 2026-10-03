import SwiftUI

struct TripSaveDraft: Identifiable {
    var id = UUID()
    let trip: Trip?
    let name: String
    let start: Date
    let end: Date
    let emoji: String
}

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
    @Published var tripSaveRecovery: TripSaveDraft?
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
    private var startupLocationCameraID: UUID?
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
    var mapMarkers: [Marker] { markers }
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
        connectionRevision = UUID(); refreshGeneration = UUID(); dataRevision = UUID()
        loading = false; refreshing = false; saving = false
        failedSaveAction = nil; canResumeFailedSave = false; tripSaveRecovery = nil
        pendingCreatedMarkers = [:]; pendingCreatedTrips = [:]
        endAddingPlace()
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
        applyNearestStartupMarker()
    }
    func refreshSelectedMarker(_ id: String) async {
        guard !demo, settings.configured, !saving else { return }
        let revision = connectionRevision, dataVersion = dataRevision, client = api
        do {
            guard let marker = try await markerRepository.detail(id, using: client) else { return }
            try Task.checkCancellation()
            guard revision == connectionRevision, dataVersion == dataRevision,
                  !saving, let index = markers.firstIndex(where: { $0.id == id }), markers[index] != marker else { return }
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
        applyNearestStartupMarker()
    }
    func noteMapInteraction() { startupMapInteracted = true }
    private func applyNearestStartupMarker() {
        guard let location = startupLocation, !startupLocationFinished, !startupMapInteracted else { return }
        guard camera == nil || camera?.id == startupLocationCameraID else { return }
        guard draft == nil, selectedMarker == nil else { return }
        guard let marker = markers.filter({ $0.coordinates.isValid }).min(by: {
            let a = Coordinates.distance(location, $0.coordinates)
            let b = Coordinates.distance(location, $1.coordinates)
            return a == b ? $0.id < $1.id : a < b
        }) else { return }
        camera = CameraCommand(points: [marker.coordinates], singlePointZoom: 15)
        startupLocationFinished = true
    }
    func applyStartupCamera(now: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) {
        guard startupCameraPending else { return }
        startupCameraPending = false
        // Do not interrupt a selection or camera action made while data was loading.
        guard tripID == nil, dayID == nil, selectedMarker == nil, draft == nil, camera == nil else { return }
        defer {
            startupLocationCameraID = camera?.id
            applyNearestStartupMarker()
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
        guard reserveEditorSave() else { return false }
        let revision = connectionRevision, client = suppliedClient ?? api
        let previous = value.trip.flatMap { trip in trips.first { $0.id == trip.id } }
        if var optimistic = previous {
            let offset = Calendar.current.dateComponents([.day], from: Date.fromDay(optimistic.startDate), to: Date.fromDay(value.start.dayString)).day ?? 0
            optimistic.name = value.name; optimistic.emoji = value.emoji; optimistic.startDate = value.start.dayString
            optimistic.endDate = Calendar.current.date(byAdding: .day, value: offset, to: Date.fromDay(optimistic.endDate))?.dayString ?? optimistic.endDate
            for index in optimistic.days.indices {
                optimistic.days[index].date = Calendar.current.date(byAdding: .day, value: offset, to: Date.fromDay(optimistic.days[index].date))?.dayString ?? optimistic.days[index].date
            }
            if let index = trips.firstIndex(where: { $0.id == optimistic.id }) { trips[index] = optimistic }
        }
        Task {
            let ok = await perform(reserved: true, expectedRevision: revision) { _ in
                var body: [String: Any] = ["name": value.name, "startDate": value.start.dayString, "emoji": value.emoji]
                if let trip = value.trip { try await client.mutate("trips/\(APIClient.id(trip.id))", method: "PUT", body: body) }
                else {
                    body["endDate"] = value.end.dayString
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
        guard draft.coordinates.isValid, !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { errorMessage = "请输入名称与有效坐标"; return false }
        let targetDay = draft.marker == nil || joinExistingTarget ? (reserved ? target : (addPlaceDay ?? day)) : nil
        let tripTarget = targetTripID ?? (reserved ? nil : addPlaceTripID)
        let revision = expectedRevision ?? connectionRevision
        var createdMarker: Marker?
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
                    created = try await client.request("markers", method: "POST", body: ["coordinates": ["latitude": draft.coordinates.latitude, "longitude": draft.coordinates.longitude], "title": draft.title, "iconType": draft.icon.rawValue, "address": draft.address, "content": draft.html])
                    guard revision == self.connectionRevision else { throw CancellationError() }
                    self.pendingCreatedMarkers[draft.id] = created
                }
                if !draft.headerImage.isEmpty { try await client.mutate("markers/\(APIClient.id(created.id))", method: "PUT", body: ["headerImage": draft.headerImage]) }
                createdMarker = created
            }
            guard revision == self.connectionRevision else { throw CancellationError() }
            if let targetDay, let marker = createdMarker ?? draft.marker,
               !self.trips.flatMap(\.days).contains(where: { $0.id == targetDay.id && $0.markerIds.contains(marker.id) }) {
                try await client.mutate(Self.dayPath(targetDay) + "/markers", method: "POST", body: ["markerId": marker.id])
            }
            if let tripTarget, let marker = createdMarker ?? draft.marker {
                try await client.mutate("trips/\(APIClient.id(tripTarget))/markers", method: "POST", body: ["markerId": marker.id])
            }
        }
        guard revision == connectionRevision else { return false }
        if ok {
            pendingCreatedMarkers[draft.id] = nil
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
            if let saved, let targetDay,
               let ti = trips.firstIndex(where: { $0.id == targetDay.tripId }),
               let di = trips[ti].days.firstIndex(where: { $0.id == targetDay.id }),
               !trips[ti].days[di].markerIds.contains(saved.id) { trips[ti].days[di].markerIds.append(saved.id) }
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
        trips[ti].days[di] = day
    }
    static func dayPath(_ day: TripDay) -> String { "trips/\(APIClient.id(day.tripId))/days/\(APIClient.id(day.id))" }
    @discardableResult func addMarker(_ marker: Marker, to day: TripDay) async -> Bool {
        addMarkerInBackground(marker, to: day)
    }
    @discardableResult
    func addMarkerInBackground(_ marker: Marker, to day: TripDay, using client: APIClient? = nil) -> Bool {
        guard var latest = trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) else { return false }
        if latest.markerIds.contains(marker.id) { return true }
        latest.markerIds.append(marker.id)
        return persistDayInBackground(latest, animated: true, using: client) {
            try await $0.mutate(Self.dayPath(day) + "/markers", method: "POST", body: ["markerId": marker.id])
        }
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
    func focus(_ marker: Marker) {
        if placeSearchPresented {
            guard draft == nil else { return }
            let place = Place(id: "saved-" + marker.id, name: marker.title, address: marker.content.address ?? "", coordinates: marker.coordinates)
            if !searchResults.contains(where: { $0.id == place.id }) { searchResults.append(place) }
            choose(place, fromMap: true)
            return
        }
        guard selectedMarker?.id != marker.id else { return }
        let detail = MarkerDetailLayout(marker: marker,
            itineraryCount: MarkerPresentation.itineraries(for: marker.id, trips: trips).count,
            hasSelectedDay: day != nil)
        selectedMarker = marker
        camera = CameraCommand(points: [marker.coordinates], detailLayout: detail)
    }
    func fly(_ points: [Coordinate]) { if !points.isEmpty { camera = CameraCommand(points: points) } }
    func create(at coordinate: Coordinate, poiName: String? = nil) {
        guard coordinate.isValid, draft?.marker == nil, !saving else { return }
        if draft?.coordinates == coordinate { return }
        if placeSearchPresented {
            let place = Place(id: UUID().uuidString, name: "", address: "", coordinates: coordinate)
            searchResults.append(place); editingSearchPlaceID = place.id
        }
        selectedSearchPlaceID = nil; draftExpanded = false
        let selectedName = poiName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var pending = draft ?? MarkerDraft(coordinates: coordinate)
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
    }
    func endAddingPlace() {
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
            if ProcessInfo.processInfo.arguments.contains("--paged-search-demo") {
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
            var ids = Set(searchResults.map(\.id))
            let additions = page.places.filter { ids.insert($0.id).inserted }
            searchResults.append(contentsOf: additions)
            if let next = page.nextPage, next > request.page {
                nextSearchRequest = PlaceSearchRequest(page: next, pageSize: page.pageSize, pageToken: page.nextPageToken)
            } else { nextSearchRequest = nil }
            searchHasMore = nextSearchRequest != nil
            searchPageRevision = UUID()
            if first {
                fly(searchResults.map(\.coordinates))

            }
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
    func clearSearch() { resetSearchSession(); searchText = "" }
    func choose(_ place: Place, fromMap: Bool = false) {
        guard place.coordinates.isValid else { return }
        if placeSearchPresented {
            guard draft == nil else { return }
            if selectedSearchPlaceID != place.id {
                selectedSearchPlaceID = place.id; addPlaceError = nil
                fly([place.coordinates])
            }
            if fromMap && !isPlaceAdded(place) { prepareSearchPlaceAddition(place) }
            return
        }
        if fromMap, selectedSearchPlaceID == place.id, draft != nil {
            draftExpanded = true
            return
        }
        selectedSearchPlaceID = place.id; draftExpanded = false
        fly([place.coordinates])
        draft = MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
    }
    var selectedSearchPlace: Place? { searchResults.first { $0.id == selectedSearchPlaceID } }
    func savedMarker(for place: Place) -> Marker? {
        // Provider POI IDs and our marker IDs are different namespaces.
        createdSearchMarkers[place.id] ?? markers.first { $0.coordinates == place.coordinates }
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
        editingSearchPlaceID = place.id
        draft = savedMarker(for: place).map(MarkerDraft.init(marker:))
            ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
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
            let value = edited ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
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
        let value = edited ?? MarkerDraft(coordinates: place.coordinates, title: place.name, address: place.address)
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
                    "title": value.title, "iconType": value.icon.rawValue, "address": value.address, "content": value.html])
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
            if let target, !isPlaceAdded(place) {
                try await client.mutate(Self.dayPath(target) + "/markers", method: "POST", body: ["markerId": marker.id])
            }
            if let targetTripID, !isPlaceAdded(place) {
                try await client.mutate("trips/\(APIClient.id(targetTripID))/markers", method: "POST", body: ["markerId": marker.id])
            }
            guard revision == connectionRevision, session == addSession else { return false }
            if let index = markers.firstIndex(where: { $0.id == marker.id }) { markers[index] = marker }
            else { markers.append(marker) }
            if let target, let ti = trips.firstIndex(where: { $0.id == target.tripId }),
               let di = trips[ti].days.firstIndex(where: { $0.id == target.id }),
               !trips[ti].days[di].markerIds.contains(marker.id) { trips[ti].days[di].markerIds.append(marker.id) }
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
        let mode = settings.mode, services = mapServices, provider = mapConfiguration.directionsProvider, server = settings.baseURL
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
                                                                  preserve: preservingPlannedGeometry),
                  !Task.isCancelled, self.routeGeneration == generation else { return }
            if planning {
                guard let restored = try? await routeProcessing.restoringCachedGeometry(segments, cache: routeCache,
                            mode: mode, provider: provider, server: server),
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
            withTransaction(transaction) { displayRoutes = displays }
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
                        let distance = route.isFallback ? nil : route.distance
                        if updated.points != points || updated.isPlanned != !route.isFallback || updated.distance != distance {
                            updated.points = points; updated.isPlanned = !route.isFallback
                            updated.distance = distance
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
        rebuildRoutes(); fly(markers.map(\.coordinates))
    }
}
struct CameraCommand: Identifiable {
    var id = UUID()
    var points: [Coordinate]
    var singlePointZoom: Double = 15
    var detailLayout: MarkerDetailLayout? = nil
    var revealDraft = false
    func viewportInsets(base: MapViewportInsets, height: Double, bottomSafeArea: Double,
                        bottomSheet: Bool) -> MapViewportInsets {
        var insets = base
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
