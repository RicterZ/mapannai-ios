import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Combine

struct TripEditorView: View {
    @ObservedObject var store: AppStore
    let trip: Trip?
    var initial: TripSaveDraft? = nil
    var body: some View { TripCreationView(store: store, trip: trip, initial: initial) }
}
/// Shared page for archive navigation and the expanded map panel.
struct DayDetailPage: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    let day: TripDay
    var showsNavigation = true
    var closeIdentifier = "archive-day-close"
    var mapIdentifier = "archive-day-map"
    let onClose: () -> Void
    let onMap: () -> Void
    @State private var editingPlaces = false
    @State private var pagingDayID: String?
    @State private var cachedDistances: [String: Double] = [:]
    // Only the date strip observes frame-by-frame progress, not the paged lists.
    @State private var pagingProgress = DayPagingProgress()
    private var days: [TripDay] { trip.days.sorted { $0.date < $1.date } }
    private var selectedDay: Binding<String> {
        Binding(get: { pagingDayID ?? day.id }, set: { id in
            guard !editingPlaces else { return }
            pagingDayID = id
        })
    }
    var body: some View {
        VStack(spacing: 0) {
            if !showsNavigation {
                HStack(spacing: 4) {
                    DayMapDateStrip(store: store, trip: trip, day: day, identifierPrefix: "day-detail-date-", pagingProgress: pagingProgress)
                        .disabled(editingPlaces)
                    if editingPlaces { DayEditingDoneButton(editing: $editingPlaces) }
                }.padding(.horizontal, 20).padding(.bottom, 4)
                    .background(Color(uiColor: .systemBackground))
            }
            TabView(selection: selectedDay) {
                ForEach(days) { date in
                    DayContentsView(store: store, day: date, cachedDistances: cachedDistances, showsDaySummary: true, showsEditingAction: false, showsEditingDone: false, editingPlaces: $editingPlaces)
                        .listStyle(.insetGrouped).scrollContentBackground(.hidden)
                        .ignoresSafeArea(.container, edges: .bottom)
                        .contentMargins(.top, 8, for: .scrollContent)
                        .background(Color(uiColor: .systemBackground))
                        .accessibilityIdentifier("day-detail-page-" + date.id)
                        .accessibilityHidden(date.id != day.id)
                        .tag(date.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea(.container, edges: .bottom)
            .background(DayPagingInteraction(enabled: !editingPlaces, progress: pagingProgress, dayIndex: days.firstIndex { $0.id == day.id } ?? 0) {
                guard let id = pagingDayID, id != day.id, !editingPlaces,
                      let next = days.first(where: { $0.id == id }) else { return }
                store.select(trip: trip, day: next, focus: false)
            })
        }
            .onChange(of: day.id) { _, id in pagingDayID = id }
            .task(id: distanceSnapshotID) {
                cachedDistances = [:]
                let distances = try? await store.cachedRouteDistances(for: days)
                guard !Task.isCancelled else { return }
                cachedDistances = distances ?? [:]
            }
            .onReceive(store.$displayRoutes) { routes in
                for route in routes {
                    if route.isPlanned, !route.isDashed,
                       let distance = route.distance, distance.isFinite, distance >= 0 {
                        cachedDistances[route.id] = distance
                    } else {
                        cachedDistances[route.id] = nil
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("第\((trip.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id } ?? 0) + 1)天")
            .navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden()
            .toolbar(showsNavigation ? .visible : .hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Image(systemName: "xmark").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("关闭日详情").accessibilityIdentifier(closeIdentifier)
                }.journeyBareBackground
                ToolbarItem(placement: .topBarTrailing) {
                    if editingPlaces { DayEditingDoneButton(editing: $editingPlaces) }
                    else {
                        Button(action: onMap) { Label("地图", systemImage: "map").foregroundStyle(Color(uiColor: .label)) }
                            .accessibilityIdentifier(mapIdentifier).buttonStyle(.plain)
                    }
                }.journeyBareBackground
            }
    }
    private struct DistanceSnapshotID: Hashable {
        let days: [TripDay]
        let markers: [Marker]
        let server: String
        let provider: MapServiceProvider
    }
    private var distanceSnapshotID: DistanceSnapshotID {
        DistanceSnapshotID(days: days, markers: store.markers, server: store.settings.baseURL,
            provider: store.mapConfiguration.directionsProvider)
    }
}

/// Disable only the horizontal page scroll during place sorting, not the vertical lists.
private struct DayPagingInteraction: UIViewRepresentable {
    let enabled: Bool
    let progress: DayPagingProgress
    let dayIndex: Int
    let onSettled: () -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator {
        var pending: DispatchWorkItem?
        var observation: NSKeyValueObservation?
        weak var observedScroll: UIScrollView?
        var idleOffset: CGFloat?
        var origin: (offset: CGFloat, index: Int)?
        var dayIndex = 0
        var progress: DayPagingProgress?
        var onSettled: () -> Void = {}
        func track(_ scroll: UIScrollView) {
            guard observedScroll !== scroll else { return }
            observedScroll = scroll; idleOffset = scroll.contentOffset.x
            observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                guard let self, scroll.bounds.width > 0 else { return }
                if scroll.isTracking || scroll.isDragging || scroll.isDecelerating {
                    if self.origin == nil { self.origin = (self.idleOffset ?? scroll.contentOffset.x, self.dayIndex) }
                    if let origin = self.origin {
                        self.progress?.position = Double(origin.index) + Double((scroll.contentOffset.x - origin.offset) / scroll.bounds.width)
                    }
                    self.observe(scroll, onSettled: self.onSettled)
                } else { self.idleOffset = scroll.contentOffset.x }
            }
        }
        deinit { pending?.cancel() }
        func observe(_ scroll: UIScrollView, onSettled: @escaping () -> Void) {
            pending?.cancel()
            let work = DispatchWorkItem { [weak self, weak scroll] in
                guard let self, let scroll else { return }
                if scroll.isTracking || scroll.isDragging || scroll.isDecelerating {
                    self.observe(scroll, onSettled: onSettled)
                } else {
                    self.origin = nil; self.idleOffset = scroll.contentOffset.x
                    onSettled()
                    self.progress?.position = nil
                }
            }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.02, execute: work)
        }
    }
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            var ancestor = view.superview
            while let parent = ancestor {
                if let scroll = pagingScroll(in: parent) {
                    scroll.isScrollEnabled = enabled
                    context.coordinator.progress = progress
                    context.coordinator.dayIndex = dayIndex
                    context.coordinator.onSettled = onSettled
                    context.coordinator.track(scroll)
                    context.coordinator.observe(scroll, onSettled: onSettled)
                    return
                }
                ancestor = parent.superview
            }
        }
    }
    private func pagingScroll(in view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView, scroll.isPagingEnabled { return scroll }
        for child in view.subviews {
            if let scroll = pagingScroll(in: child) { return scroll }
        }
        return nil
    }
}

/// Cover first; category artwork only when no cover is available.
struct DayPlaceArtwork: View {
    let marker: Marker
    var fallbackBackground = Color(uiColor: .secondarySystemBackground)
    @State private var photo: UIImage?
    private var url: URL? { marker.content.headerImage.flatMap(imageURL) }
    var body: some View {
        Group {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
            } else {
                PlaceIconView(emoji: marker.icon.emoji, size: 30)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(fallbackBackground)
            }
        }.task(id: url) {
            photo = nil
            guard let url else { return }
            let loaded = await JourneyPhotoCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            photo = loaded
        }
    }
}

struct DayEditingDoneButton: View {
    @Binding var editing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Button {
            withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) { editing = false }
        } label: {
            Image(systemName: "checkmark").font(.system(size: 20, weight: .medium))
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .accessibilityLabel("完成编辑").accessibilityIdentifier("day-edit-done")
    }
}

struct DayContentsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var dayTitleSize: CGFloat = 24
    @ObservedObject var store: AppStore
    let day: TripDay
    var cachedDistances: [String: Double] = [:]
    var showsDaySummary = false
    var showsEditingAction = true
    var showsEditingDone = true
    @Environment(\.colorScheme) private var colorScheme
    @State private var chainEditor: ChainEditRequest?
    @State private var scheduleEditor: RouteScheduleRequest?
    @State private var fullScreenEditing = false
    var isEditingWorkspace = false
    @State private var editingDistances: [String: Double] = [:]
    @State private var deletingDay = false
    @State private var deletingChain: Int?
    @State private var nativeRouteGeometry = NativeRouteGeometryStorage()
    private var nativeRouteFrames: [String: CGRect] { nativeRouteGeometry.frames }
    @State private var collapsedRoutes: Set<Int> = []
    @State private var dragDiagnosticUpdates = 0
    @State private var sortingPlaces = false
    @Binding var editingPlaces: Bool
    @State private var selectedPlaces: Set<DayPlaceReference> = []
    @State private var transferRequest: DayPlaceTransferRequest?
    @State private var deletingPlaces: Set<DayPlaceReference> = []
    var body: some View {
        List(selection: $selectedPlaces) {
            if showsDaySummary {
                Section {
                    VStack(alignment: .leading, spacing: 5) {
                        if let title = day.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(title).font(.system(size: dayTitleSize, weight: .semibold)).foregroundStyle(.primary)
                        }
                        Text("\(day.markerIds.count) 个地点 · \(day.chains.count) 条路线").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 16)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 12))
                    .accessibilityIdentifier("day-detail-summary")
                }
            }
            Group {

            ForEach(Array(day.chains.enumerated()), id: \.offset) { index, chain in
                Section {
                    routeHeader(index: index, chain: chain)
                    if !collapsedRoutes.contains(index) {
                        ForEach(chain.enumerated().map { RoutePlaceSlot(markerID: $0.element, position: $0.offset) }) { slot in
                            let id = slot.markerID
                            let position = slot.position
                            let reference = DayPlaceReference(markerID: id, routeIndex: index)
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                VStack(spacing: 0) {
                                    RoutePlaceSelectionButton(store: store, dayID: day.id, routeIndex: index, marker: marker, tint: routeTint, editing: editingPlaces, selected: selectedPlaces.contains(reference), toggleSelection: {
                                        if selectedPlaces.contains(reference) { selectedPlaces.remove(reference) }
                                        else { selectedPlaces.insert(reference) }
                                    }, stop: day.scheduledRoute(at: index)?.stops[position], showsSchedule: !editingPlaces, editPlaces: { beginPlaceEditing() }, editSchedule: {
                                        if let route = day.scheduledRoute(at: index) { openSchedule(route, position: position, transport: false) }
                                    })

                                }
                                .padding(.bottom, editingPlaces ? 0 : position == chain.count - 1 ? 8 : 0)
                                .background {
                                    RouteSequenceLine(first: position == 0, last: position == chain.count - 1)
                                        .stroke(routeTint.opacity(editingPlaces ? 0 : 0.24), lineWidth: 1)
                                        .allowsHitTesting(false).accessibilityHidden(true)
                                }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["\(index)/\(position)": geometry.frame(in: .global)])
                    })
                                .listRowBackground(Group {
                                    Color(uiColor: .systemBackground)
                                })
                                .listRowSeparator(.hidden, edges: .all)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .modifier(DayPlaceEditingDrag(enabled: editingPlaces && store.canEditItinerary,
                                    payload: "day-place/" + day.id + "/" + id + "/" + String(index)))
                                .tag(reference)
                                .selectionDisabled()
                                .environment(\.editMode, .constant(.inactive))

                                .accessibilityAction(named: "移出路线") { makeDayPlaceUnplanned(id, from: index) }
                                if editingPlaces, let route = day.scheduledRoute(at: index) {
                                    RoutePlaceSelectionButton(store: store, dayID: day.id, routeIndex: index,
                                        marker: marker, tint: routeTint, editing: true, stop: route.stops[position],
                                        showsIdentity: false, editSchedule: { openSchedule(route, position: position, transport: false) })
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .listRowSeparator(.hidden).listRowBackground(Color(uiColor: .systemBackground))
                                        .moveDisabled(true).selectionDisabled()
                                        .environment(\.editMode, .constant(.inactive))
                                        .modifier(ArrangementDuringSorting(collapsed: sortingPlaces))
                                }
                                if position + 1 < chain.count {
                                    transportRow(chain: chain, index: index, position: position)
                                        .background {
                                            if !editingPlaces {
                                                RouteSequenceLine(first: false, last: false)
                                                    .stroke(routeTint.opacity(0.24), lineWidth: 1)
                                                    .allowsHitTesting(false).accessibilityHidden(true)
                                            }
                                        }
                                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                        .listRowSeparator(.hidden)
                                        .moveDisabled(true).selectionDisabled()
                                        .environment(\.editMode, .constant(.inactive))
                                        .modifier(ArrangementDuringSorting(collapsed: sortingPlaces && editingPlaces))
                                }

                            }
                        }
                        .onMove { offsets, destination in
                            guard store.canEditItinerary,
                                  store.trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) == day else {
                                store.errorMessage = "行程已更新，请重新排序。"; return
                            }
                            var orders = day.chains
                            orders[index].move(fromOffsets: offsets, toOffset: destination)
                            var updated = day; updated.setRouteOrders(orders)
                            if store.tripPlacesPreview,
                               let ti = store.trips.firstIndex(where: { $0.id == day.tripId }),
                               let di = store.trips[ti].days.firstIndex(where: { $0.id == day.id }) {
                                store.trips[ti].days[di] = updated
                                store.rebuildRoutes(preservingPlannedGeometry: true)
                            } else { _ = store.saveDayInBackground(updated) }
                        }
                        .moveDisabled(!editingPlaces || !store.canEditItinerary)
                    }

                }
            }
            let linked = Set(day.chains.flatMap { $0 })
            let available = Set(store.markers.map(\.id))
            let unlinked = day.markerIds.filter { !linked.contains($0) && available.contains($0) }
            if editingPlaces || !unlinked.isEmpty {
            Section {
                    JourneyPlaceGroupHeading(title: "未安排", count: unlinked.count)
                        .accessibilityIdentifier("day-unplanned-heading")
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                        })
                    if unlinked.isEmpty {
                        Color.clear.frame(height: 60)
                            .contentShape(Rectangle())
                            .accessibilityLabel("未安排地点拖放区域")
                            .accessibilityIdentifier("day-unplanned-drop-area")
                            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                            .background(GeometryReader { geometry in
                                Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                            })
                    }
                    ForEach(unlinked, id: \.self) { id in
                        let reference = DayPlaceReference(markerID: id, routeIndex: nil)
                        if let marker = store.markers.first(where: { $0.id == id }) {
                            RoutePlaceSelectionButton(store: store, dayID: day.id, routeIndex: nil,
                                marker: marker, tint: .secondary, editing: editingPlaces,
                                selected: selectedPlaces.contains(reference), toggleSelection: {
                                    if selectedPlaces.contains(reference) { selectedPlaces.remove(reference) }
                                    else { selectedPlaces.insert(reference) }
                                }, editPlaces: { beginPlaceEditing() })
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global), "source/" + id: geometry.frame(in: .global)])
                                })
                                .modifier(DayPlaceEditingDrag(enabled: editingPlaces && store.canEditItinerary,
                                    payload: "day-place/" + day.id + "/" + id))
                                .tag(reference)
                                .selectionDisabled()
                                .environment(\.editMode, .constant(.inactive))
                                .accessibilityAction(named: "从当天移除") {
                                    Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                }

                        }
                    }
            }
            }
            }.listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
            if !editingPlaces {
            Section {
                HStack(spacing: 18) {
                    Button { store.beginAddingPlace(to: day) } label: { Label("添加地点", systemImage: "plus").frame(minHeight: 48).contentShape(Rectangle()) }
                        .accessibilityIdentifier("day-search-add-place")
                    Button { beginPlaceEditing() } label: { Label("编辑模式", systemImage: "slider.horizontal.3").frame(minHeight: 48).contentShape(Rectangle()) }
                        .accessibilityIdentifier("day-edit-places")
                    Button { chainEditor = ChainEditRequest(day: day, index: nil, ids: []) } label: {
                        Label("新建路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath").frame(minHeight: 48).contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .labelStyle(.titleAndIcon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Color(uiColor: .label))
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(GeometryReader { geometry in
                    Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                })
                .listRowBackground(Color.clear).listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }.font(.body)
            }

        }
        .environment(\.editMode, .constant(editingPlaces ? .active : .inactive))
        .animation(AppMotion.listMutation(reduceMotion: reduceMotion), value: editingPlaces)
        .onChange(of: editingPlaces) { _, editing in if !editing { selectedPlaces = [] } }
        .safeAreaInset(edge: .top, spacing: 0) {
            if editingPlaces && showsEditingDone {
                HStack { Spacer(); DayEditingDoneButton(editing: $editingPlaces) }
                    .padding(.horizontal, 16).background(Color(uiColor: .systemBackground))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if editingPlaces && !selectedPlaces.isEmpty { placeEditingBar }
        }
        .edgeAttachedPanel(isPresented: Binding(get: { transferRequest != nil }, set: { if !$0 { transferRequest = nil } }), dimsBackground: true) {
            if let request = transferRequest {
                DayPlaceTransferPicker(store: store, request: request, onCancel: { transferRequest = nil }) {
                    selectedPlaces = []; editingPlaces = false; transferRequest = nil
                }
            }
        }
        .sheet(isPresented: Binding(get: { !deletingPlaces.isEmpty }, set: { if !$0 { deletingPlaces = [] } })) {
            let ids = deletingPlaces
            let sourceDay = day
            let markerIDs = Set(ids.map(\.markerID))
            let submit: (TripDay) -> Void = { updated in
                deletingPlaces = []
                guard store.trips.first(where: { $0.id == sourceDay.tripId })?.days.first(where: { $0.id == sourceDay.id }) == sourceDay else {
                    store.errorMessage = "行程已更新，请重新选择地点。"
                    return
                }
                if store.saveDayInBackground(updated) { selectedPlaces.subtract(ids) }
            }
            let choices = [DeletionConfirmationChoice(id: "today", title: "从今天删除") {
                submit(markerIDs.reduce(sourceDay) { $0.removing($1) })
            }] + sourceDay.chains.indices.filter { index in
                sourceDay.chains[index].contains { markerIDs.contains($0) }
            }.map { index in
                DeletionConfirmationChoice(id: "route-\(index)", title: "从路线\(index + 1)删除") {
                    let references = Set(sourceDay.chains[index].filter { markerIDs.contains($0) }
                        .map { DayPlaceReference(markerID: $0, routeIndex: index) })
                    submit(sourceDay.removingReferences(references, keepMembership: true))
                }
            }
            DeletionConfirmationView(store: store, title: "删除地点", message: "请选择删除范围。从路线删除会保留当天地点；从今天删除会清理当天所有路线引用。收藏和其他日期不受影响。", kind: "day-places", offersExclusiveMarkers: false, choices: choices) { _ in }

        }
        .onChange(of: day.placeReferences) { _, _ in selectedPlaces = [] }
        .onChange(of: day.chains) { _, _ in selectedPlaces = [] }
        .onChange(of: day.id) { _, _ in selectedPlaces = []; editingPlaces = false }
        .listSectionSpacing(8)
        .environment(\.defaultMinListRowHeight, 0)
        .onPreferenceChange(NativeRouteFrames.self) { nativeRouteGeometry.frames = $0 }
        .background(NativePlaceListDrop(frames: nativeRouteFrames, frameSource: { nativeRouteGeometry.frames }, prefix: "day-place/" + day.id + "/", onDiagnostics: { dragDiagnosticUpdates = $0 }, onDrop: { store.finishRouteDrop() }, onSorting: { active in
            // Collapse immediately so drop feedback measures the settled layout.
            if active {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { sortingPlaces = true }
            } else {
                withAnimation(AppMotion.crossfade(reduceMotion: reduceMotion)) { sortingPlaces = false }
            }
        }, sourceTargets: Dictionary(uniqueKeysWithValues: day.chains.enumerated().flatMap { route, ids in
            ids.enumerated().map { position, id in (id + "/" + String(route), "\(route)/\(position)") }
        })) { id, route in
            let payload = id.split(separator: "/")
            guard let marker = payload.first else { return }
            let markerID = String(marker)
            let source = payload.count > 1 ? Int(payload[1]) : nil
            if route == "unplanned" { makeDayPlaceUnplanned(markerID, from: source, animated: false); return }
            let parts = route.split(separator: "/")
            guard let first = parts.first, let index = Int(first) else { return }
            let position = parts.count > 1 ? Int(parts[1]) : nil
            let insertion = position.map { $0 + (parts.last == "after" ? 1 : 0) }
            moveDayPlace(markerID, from: source, to: index, at: insertion)
        })
        .sheet(item: $chainEditor) { ChainEditorView(store: store, request: $0) }
        .sheet(item: Binding(get: { isEditingWorkspace ? nil : scheduleEditor }, set: { if !isEditingWorkspace { scheduleEditor = $0 } })) {
            RouteScheduleEditor(store: store, request: $0)
        }
        .navigationDestination(item: Binding(get: { isEditingWorkspace ? scheduleEditor : nil }, set: { if isEditingWorkspace { scheduleEditor = $0 } })) {
            RouteScheduleEditor(store: store, request: $0, embedded: true)
        }
        .fullScreenCover(isPresented: $fullScreenEditing) {
            DayEditingWorkspace(store: store, tripID: day.tripId, dayID: day.id)
        }
        .task(id: EditingDistanceSnapshot(day: day, markers: store.markers, server: store.settings.baseURL, planning: store.settings.planning, provider: store.mapConfiguration.directionsProvider)) {
            guard isEditingWorkspace else { return }
            editingDistances = [:]
            await store.planEditingDistances(for: day) { editingDistances = $0 }
        }
        .sheet(isPresented: $deletingDay) { DayDeletionView(store: store, day: day) }
        .sheet(isPresented: Binding(get: { deletingChain != nil }, set: { if !$0 { deletingChain = nil } })) {
            if let index = deletingChain {
                let sourceDay = day
                DeletionConfirmationView(store: store, title: "删除路线", message: "删除路线\(index + 1)的访问顺序，保留当天地点、收藏和其他路线。", kind: "route", offersExclusiveMarkers: false, allowsQueuedWrites: true) { _ in
                    deletingChain = nil
                    guard var latest = store.trips.first(where: { $0.id == sourceDay.tripId })?.days.first(where: { $0.id == sourceDay.id }),
                          latest == sourceDay, latest.chains.indices.contains(index) else {
                        store.errorMessage = "行程已更新，请重新选择路线。"
                        return
                    }
                    latest.removeRoute(at: index)
                    if store.saveDayInBackground(latest, animated: !reduceMotion) {
                        collapsedRoutes = Set(collapsedRoutes.filter { $0 != index }.map { $0 > index ? $0 - 1 : $0 })
                    }
                }
            }
        }
    }
    private func beginPlaceEditing(_ id: String? = nil) {
        guard store.canEditItinerary else { return }
        guard isEditingWorkspace else { fullScreenEditing = true; return }
        withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) {
            editingPlaces = true
            if let id { selectedPlaces.insert(DayPlaceReference(markerID: id, routeIndex: nil)) }
        }
    }
    private var placeEditingBar: some View {
        VStack(spacing: 0) {
            HStack {
                Button(selectedPlaces.count == day.placeReferences.count ? "取消全选" : "全选") {
                    selectedPlaces = selectedPlaces.count == day.placeReferences.count ? [] : day.placeReferences
                }.frame(minHeight: 44).disabled(day.markerIds.isEmpty)
                    .accessibilityIdentifier("day-select-all")
                Spacer()
                Text("已选 \(selectedPlaces.count) 个地点").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 12) {
                Button { transferRequest = DayPlaceTransferRequest(source: day, ids: Set(selectedPlaces.map(\.markerID)), references: selectedPlaces, copy: false) } label: {
                    Label("移动", systemImage: "arrow.right").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("day-selection-move")
                Button { transferRequest = DayPlaceTransferRequest(source: day, ids: Set(selectedPlaces.map(\.markerID)), references: selectedPlaces, copy: true) } label: {
                    Label("复制", systemImage: "square.on.square").frame(maxWidth: .infinity, minHeight: 44)
                }.accessibilityIdentifier("day-selection-copy")
                Button(role: .destructive) { deletingPlaces = selectedPlaces } label: {
                    Label("删除", systemImage: "trash").frame(maxWidth: .infinity, minHeight: 44)
                }.foregroundStyle(.red).accessibilityIdentifier("day-selection-delete")
            }.buttonStyle(DayEditingActionStyle()).font(.subheadline.weight(.medium))
                .disabled(selectedPlaces.isEmpty || !store.canEditItinerary)
        }
        .font(.subheadline).tint(Color(uiColor: .label))
        .padding(.horizontal, 16).padding(.bottom, 8)
        .background(Color(uiColor: .systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("day-place-editing-bar")
    }
    private var routeTint: Color { DayRouteTint.color(day.colorIndex ?? 0) }
    private var daySummary: String {
        let days = store.trips.first { $0.id == day.tripId }?.days.sorted { $0.date < $1.date } ?? []
        let index = days.firstIndex { $0.id == day.id } ?? 0
        let summary = JourneyDaySummary(day: day, index: index, markers: store.markers)
        return summary.theme ?? "\(summary.count) 个地点 · \(day.chains.count) 条路线"
    }
    private func makeDayPlaceUnplanned(_ id: String, from source: Int?, animated: Bool = true) {
        guard let ti = store.trips.firstIndex(where: { $0.id == day.tripId }),
              let di = store.trips[ti].days.firstIndex(where: { $0.id == day.id }),
              store.canEditItinerary else { return }
        var current = store.trips[ti].days[di]
        guard current == day, let source, current.chains.indices.contains(source) else { return }
        current = current.removingReferences([DayPlaceReference(markerID: id, routeIndex: source)], keepMembership: true)
        if store.tripPlacesPreview {
            withAnimation(animated ? AppMotion.listMutation(reduceMotion: reduceMotion) : nil) { store.trips[ti].days[di] = current }
            store.rebuildRoutes(preservingPlannedGeometry: true)
        } else {
            _ = store.saveDayInBackground(current, animated: animated && !reduceMotion)
        }
    }

    private func moveDayPlace(_ id: String, from source: Int?, to index: Int, at insertion: Int? = nil) {
        guard let ti = store.trips.firstIndex(where: { $0.id == day.tripId }),
              let di = store.trips[ti].days.firstIndex(where: { $0.id == day.id }) else { return }
        var current = store.trips[ti].days[di]
        guard store.canEditItinerary, current.chains.indices.contains(index),
              current.chains == day.chains, current.markerIds.contains(id) else { return }
        let previous = current.chains
        var orders = current.chains
        var destination = min(current.chains[index].count, max(0, insertion ?? current.chains[index].count))
        if let source {
            guard current.chains.indices.contains(source), let old = current.chains[source].firstIndex(of: id) else { return }
            orders[source].remove(at: old)
            if source == index, old < destination { destination -= 1 }
        }
        if !orders[index].contains(id) {
            orders[index].insert(id, at: min(destination, orders[index].count))
        }
        current.setRouteOrders(orders)
        guard current.chains != previous else { return }
        if store.tripPlacesPreview {
            var transaction = Transaction(); transaction.disablesAnimations = true
            withTransaction(transaction) { store.trips[ti].days[di] = current }
            store.rebuildRoutes(preservingPlannedGeometry: true)
        } else {
            _ = store.saveDayInBackground(current, animated: false)
        }
    }

    private func routeHeader(index: Int, chain: [String]) -> some View {
                    HStack(spacing: 0) {
                        HStack(alignment: .top, spacing: 9) {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("路线 \(index + 1)").font(.body.weight(.semibold)).foregroundStyle(.primary).fixedSize()
                                    Spacer(minLength: 8)
                                    if !editingPlaces {
                                        Text("\(chain.count) 个地点").font(.caption).foregroundStyle(.secondary).fixedSize()
                                    }
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("路线 \(index + 1)").font(.body.weight(.semibold)).foregroundStyle(.primary)
                                    if !editingPlaces {
                                        Text("\(chain.count) 个地点").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(.leading, 16)
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("route-heading-\(index)")
                        if !editingPlaces { Button {
                            withAnimation(AppMotion.disclosure(reduceMotion: reduceMotion)) {
                                if collapsedRoutes.contains(index) { collapsedRoutes.remove(index) }
                                else { collapsedRoutes.insert(index) }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .rotationEffect(.degrees(collapsedRoutes.contains(index) ? 0 : 90))
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: true)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("\(collapsedRoutes.contains(index) ? "展开" : "收起")路线 \(index + 1)")
                        .accessibilityValue(collapsedRoutes.contains(index) ? "已收起" : "已展开")
                        .accessibilityIdentifier("route-toggle-\(index)") }
                        if !editingPlaces {
                            Menu {
                                Button("编辑行程", systemImage: "slider.horizontal.3") { beginPlaceEditing() }
                                Button("删除路线", systemImage: "trash", role: .destructive) { deletingChain = index }
                                    .disabled(!store.canEditItinerary)
                            } label: {
                                Image(systemName: "ellipsis").frame(width: 44, height: 44).contentShape(Rectangle())
                            }.buttonStyle(.borderless).foregroundStyle(.secondary)
                                .accessibilityLabel("路线操作").accessibilityIdentifier("route-actions-\(index)")
                        }
                        if ProcessInfo.processInfo.arguments.contains("--route-drag-diagnostics"), index == 0 {
                            Text(String(dragDiagnosticUpdates)).font(.caption)
                                .accessibilityLabel("Route drag diagnostics")
                                .accessibilityIdentifier("route-drag-diagnostics")
                                .accessibilityValue(String(dragDiagnosticUpdates))
                        }
                    }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["\(index)/header": geometry.frame(in: .global)])
                    })
                    .accessibilityAction(named: "编辑行程") { beginPlaceEditing() }
                    .selectionDisabled()
                    .font(.body)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
    }

    @ViewBuilder private func transportRow(chain: [String], index: Int, position: Int) -> some View {
        if let route = day.scheduledRoute(at: index) {
            RouteTransportRow(leg: route.leg(at: position),
                distance: routeDistance(chain: chain, index: index, position: position + 1),
                tint: routeTint, editing: editingPlaces) {
                    openSchedule(route, position: position, transport: true)
                }.padding(.leading, editingPlaces ? 33 : 0)
                    .accessibilityIdentifier("route-\(index)-transport-\(position)")
        } else if let distance = routeDistance(chain: chain, index: index, position: position + 1) {
            Text(distance).font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading).padding(.leading, 34)
        }
    }

    private func openSchedule(_ route: RouteChain, position: Int, transport: Bool) {
        guard editingPlaces, route.stops.indices.contains(position), !transport || route.stops.indices.contains(position + 1) else { return }
        let names = Dictionary(store.markers.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        scheduleEditor = RouteScheduleRequest(day: day, route: route, position: position, isTransport: transport,
            fromTitle: names[route.stops[position].markerId] ?? "地点",
            toTitle: transport ? names[route.stops[position + 1].markerId] ?? "地点" : nil)
    }
    private func routeDistance(chain: [String], index: Int, position: Int) -> String? {
        #if DEBUG
        if store.demo, ProcessInfo.processInfo.arguments.contains("--route-distance-preview"), position > 0, position < chain.count {
            return position == 1 ? "850 m" : "1.2 km"
        }
        #endif
        guard position > 0, position < chain.count else { return nil }
        let id = "\(day.id)|\(index)|\(position)|\(chain[position - 1])|\(chain[position])"
        if isEditingWorkspace {
            guard let distance = editingDistances[id], distance.isFinite, distance > 0 else { return nil }
            return distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
        }
        let route = store.displayRoutes.first { $0.id == id }
        guard let distance = route.flatMap({ $0.isPlanned && !$0.isDashed ? $0.distance : nil }) ?? cachedDistances[id],
              distance.isFinite, distance >= 0 else { return nil }
        return distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
    }

}
/// Observe optimistic local membership directly, independently of the parent
/// row's captured position and later route geometry/distance publications.
private struct RoutePlaceSelectionButton: View {
    @ObservedObject var store: AppStore
    let dayID: String
    let routeIndex: Int?
    let marker: Marker
    let tint: Color
    var editing = false
    var selected = false
    var toggleSelection: () -> Void = {}
    var stop: ChainStop? = nil
    var showsIdentity = true
    var showsSchedule = true
    var editPlaces: () -> Void = {}
    var editSchedule: () -> Void = {}
    private var ordinal: String {
        guard let routeIndex, let day = store.trips.lazy.flatMap(\.days).first(where: { $0.id == dayID }),
              day.chains.indices.contains(routeIndex),
              let position = day.chains[routeIndex].firstIndex(of: marker.id) else { return "" }
        return String(position + 1)
    }
    private var accessibilityPrefix: String {
        routeIndex.map { "route-\($0)" } ?? "day"
    }
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var identityHeight: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var addressHeight: CGFloat = 14
    private var informationHeight: CGFloat { identityHeight + 6 + addressHeight }
    var body: some View {
        VStack(spacing: 0) {
        if showsIdentity { HStack(alignment: editing ? .center : .top, spacing: 9) {
            if editing {
                Button(action: toggleSelection) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(selected ? Color.accentColor : Color(uiColor: .tertiaryLabel))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                }.buttonStyle(DayPlaceUnhighlightedButtonStyle())
                    .accessibilityLabel(selected ? "取消选择地点" : "选择地点")
                    .accessibilityIdentifier("\(accessibilityPrefix)-select-\(marker.id)")
                    .accessibilityValue(selected ? "已选中" : "未选中")
            } else if let routeIndex {
            RouteOrdinalLabel(store: store, dayID: dayID, routeIndex: routeIndex, markerID: marker.id, tint: tint)
                    .frame(width: 24, height: 24)
                    .background(Color(uiColor: .systemBackground), in: Circle())
                    .overlay { Circle().stroke(Color(uiColor: .separator), lineWidth: 0.7) }
                    .opacity(editing ? 0 : 1)
                    .accessibilityHidden(editing)
            } else {
                Color.clear.frame(width: 24, height: 24).allowsHitTesting(false).accessibilityHidden(true)
            }
            Button {
                if editing { toggleSelection() }
                else if store.canActivateRouteRow { store.selectMapMarker(marker) }
            } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .center, spacing: 8) {
                            PlaceIconView(emoji: marker.icon.emoji, size: editing ? 24 : identityHeight)
                                .frame(width: editing ? 24 : identityHeight, height: editing ? 24 : identityHeight)
                            Group {
                                if editing {
                                    Text(marker.title).font(.body.weight(.semibold)).lineLimit(2)
                                } else {
                                    Text(marker.title).font(.system(size: 18, weight: .semibold))
                                        .lineLimit(1).truncationMode(.tail)
                                        .frame(height: identityHeight, alignment: .leading)
                                }
                            }
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("\(accessibilityPrefix)-marker-\(marker.id)").accessibilityValue(ordinal)
                            .accessibilityAction(named: "编辑行程", editPlaces)
                        }
                        if !editing, let address = marker.content.address, !address.isEmpty {
                            Text(address).font(.caption2).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                                .frame(height: addressHeight, alignment: .leading)
                                .accessibilityIdentifier("\(accessibilityPrefix)-address-\(marker.id)")
                        }
                    }.frame(maxWidth: .infinity, minHeight: editing ? 0 : informationHeight, alignment: .topLeading)
                    if !editing && !typeSize.isAccessibilitySize { scheduleButton.layoutPriority(1) }
                }
                if !editing && typeSize.isAccessibilitySize { scheduleButton }
                if !editing {
                    if marker.content.headerImage.flatMap(imageURL) != nil {
                        Color.clear.frame(height: 140)
                            .accessibilityElement()
                            .accessibilityLabel("地点照片")
                            .accessibilityIdentifier("\(accessibilityPrefix)-cover-\(marker.id)")
                            .background {
                                GeometryReader { geometry in
                                    DayPlaceArtwork(marker: marker)
                                        .frame(width: geometry.size.width, height: geometry.size.height)
                                        .clipped().allowsHitTesting(false)
                                }.allowsHitTesting(false)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    if let note = stop?.note, !note.isEmpty { ItineraryNote(text: note, allowsExpansion: false, collapsedLineLimit: 3) }
                }
            }
            .contentShape(Rectangle())
            }.buttonStyle(DayPlaceUnhighlightedButtonStyle())
        } }
            if editing, showsSchedule, let stop {
                Button(action: editSchedule) {
                VStack(alignment: .leading, spacing: 0) {
                    Divider()
                    HStack {
                        Text(stop.summary.isEmpty ? "安排游览时间" : stop.summary).monospacedDigit()
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                    }.font(.system(size: 14, weight: .regular)).foregroundStyle(Color.accentColor)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    if let note = stop.note, !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(note).font(.footnote).foregroundStyle(Color(uiColor: .secondaryLabel))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, 12)
                            .accessibilityIdentifier("\(accessibilityPrefix)-schedule-note-\(marker.id)")
                    }
                }
                }.buttonStyle(.borderless)
                    .foregroundStyle(Color.accentColor).padding(.leading, 33).padding(.top, 12)
                    .accessibilityIdentifier("\(accessibilityPrefix)-schedule-\(marker.id)")
            }
        }.padding(.top, editing ? (showsIdentity ? 12 : 0) : 8).padding(.bottom, editing ? 0 : 8)
            .frame(minHeight: editing && showsIdentity ? 60 : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityAddTraits(editing && selected ? [.isSelected] : [])
    }
    @ViewBuilder private var scheduleButton: some View {
        if let stop, !stop.summary.isEmpty {
            VStack {
                VStack(alignment: .trailing, spacing: 3) {
                    Text(stop.startTime ?? "--:--").font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                    if let duration = stop.durationMinutes {
                        Text(RouteScheduleText.duration(duration)).font(.caption2).foregroundStyle(.secondary)
                    }
                }.monospacedDigit().fixedSize()
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .frame(minWidth: 44, minHeight: informationHeight, alignment: .center)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
            }.allowsHitTesting(false).accessibilityLabel("游览安排")
                .accessibilityIdentifier("\(accessibilityPrefix)-schedule-\(marker.id)").accessibilityValue(stop.summary)
        }
    }
}

private struct DayPlaceUnhighlightedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

private struct RouteSequenceLine: Shape {
    let first: Bool
    let last: Bool
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: 12, y: first ? 30 : 0))
            path.addLine(to: CGPoint(x: 12, y: last ? 30 : rect.height))
        }
    }
}

struct DayPlaceIdentity: View {
    let marker: Marker
    var editing = false
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            DayPlaceArtwork(marker: marker).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 4) {
                Text(marker.title).font(.body.weight(.medium)).foregroundStyle(.primary)
                    .lineLimit(1).truncationMode(.tail)
                if !editing, let address = marker.content.address, !address.isEmpty {
                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.frame(maxWidth: .infinity, minHeight: editing ? 48 : 44, alignment: .leading).padding(.vertical, editing ? 10 : 6)
    }
}

private struct DayEditingActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(enabled ? 1 : 0.35)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// Keep day identity while lowering saturation only in the itinerary's decorative axis.
enum DayRouteTint {
    static func color(_ index: Int) -> Color {
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        UIColor(Theme.color(index)).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        return Color(uiColor: UIColor { traits in
            UIColor(hue: hue, saturation: saturation * 0.42,
                    brightness: traits.userInterfaceStyle == .dark ? 0.78 : 0.53, alpha: 1)
        })
    }
}

/// The dragged cell may stay retained by UIKit while SwiftUI moves its hosting
/// row. Bind the actual numeral to the local snapshot, not to a later host redraw.
private struct RouteOrdinalLabel: UIViewRepresentable {
    let store: AppStore
    let dayID: String
    let routeIndex: Int
    let markerID: String
    let tint: Color
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "route-\(routeIndex)-ordinal-\(markerID)"
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.textColor = UIColor(tint)
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        context.coordinator.subscription = store.$trips.sink { [weak label] trips in
            guard let label else { return }
            let day = trips.lazy.flatMap(\.days).first { $0.id == dayID }
            let position = day.flatMap { day in
                day.chains.indices.contains(routeIndex) ? day.chains[routeIndex].firstIndex(of: markerID) : nil
            }
            label.text = position.map { String($0 + 1) } ?? ""
            label.invalidateIntrinsicContentSize()
        }
    }
    static func dismantleUIView(_ label: UILabel, coordinator: Coordinator) { coordinator.subscription?.cancel() }
    final class Coordinator { var subscription: AnyCancellable? }
}

/// A slot changes identity when its contents or ordinal change. Native list drag
/// snapshots must not retain the old content/number at a newly occupied position.
private struct RoutePlaceSlot: Identifiable {
    let markerID: String
    let position: Int
    var id: String { "\(position)/\(markerID)" }
}

struct ChainEditRequest: Identifiable { var id = UUID(); var day: TripDay; var index: Int?; var ids: [String] }
struct ChainEditorView: View {
    @ObservedObject var store: AppStore
    let request: ChainEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    @State private var error: String?
    @State private var query = ""
    @FocusState private var searchFocused: Bool
    private var candidates: [Marker] {
        let members = Set(request.day.markerIds)
        return store.markers.filter {
            members.contains($0.id) && !ids.contains($0.id) &&
            (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || ($0.content.address ?? "").localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    if ids.isEmpty {
                        Text("从下方添加地点，按访问顺序排列。")
                            .font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 12)
                            .deleteDisabled(true).moveDisabled(true)
                    }
                    ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                        if let marker = store.markers.first(where: { $0.id == id }) {
                            HStack(spacing: 12) {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit())
                                    .foregroundStyle(.tertiary).frame(width: 24)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(marker.title).font(.body.weight(.medium))
                                    if let address = marker.content.address, !address.isEmpty {
                                        Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.padding(.vertical, 8)
                            }.accessibilityIdentifier("chain-selected-" + id)
                        }
                    }.onMove { from, to in ids.move(fromOffsets: from, toOffset: to) }
                        .onDelete { ids.remove(atOffsets: $0) }
                } header: {
                    HStack {
                        JourneyEditorHeading(title: "访问顺序")
                        Spacer()
                        Text("\(ids.count) 个地点").font(.footnote).foregroundStyle(.secondary)
                    }.textCase(nil).padding(.bottom, 8)
                } footer: {
                    Text("拖动右侧手柄调整顺序；移除仅影响这条路线。")
                        .font(.footnote).padding(.top, 4)
                }
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("搜索当天地点", text: $query).focused($searchFocused)
                            .accessibilityIdentifier("chain-candidate-search")
                    }.padding(.vertical, 6).deleteDisabled(true).moveDisabled(true)
                    ForEach(candidates) { marker in
                        Button { ids.append(marker.id); searchFocused = false } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(marker.title).font(.body.weight(.medium))
                                    if let address = marker.content.address, !address.isEmpty {
                                        Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "plus").font(.system(size: 16))
                                    .frame(width: 32, height: 32)
                                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: Circle())
                            }.foregroundStyle(.primary).padding(.vertical, 8).contentShape(Rectangle())
                        }.buttonStyle(.plain).deleteDisabled(true).moveDisabled(true)
                            .accessibilityIdentifier("chain-add-marker-\(marker.id)")
                    }
                    if candidates.isEmpty {
                        Text(query.isEmpty ? "当天地点已全部在路线中" : "没有匹配的地点")
                            .font(.footnote).foregroundStyle(.secondary).padding(.vertical, 8)
                            .deleteDisabled(true).moveDisabled(true)
                    }
                } header: {
                    JourneyEditorHeading(title: "添加地点").textCase(nil).padding(.bottom, 8)
                }
                if let error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                        .listRowBackground(Color.clear).deleteDisabled(true).moveDisabled(true)
                }
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
            .scrollDismissesKeyboard(.interactively)
            .frame(maxWidth: 560).frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground))
            .accessibilityIdentifier("chain-editor-list")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                JourneyEditorSubmit(title: request.index == nil ? "创建路线" : "保存路线",
                    enabled: store.canEditItinerary && (request.index != nil || !ids.isEmpty),
                    identifier: "save-chain-editor", background: Color(uiColor: .systemBackground), action: save)
            }
            .navigationTitle(request.index == nil ? "新的路线" : "编辑路线").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("取消").accessibilityIdentifier("cancel-chain-editor")
                }
            }
        }.tint(Color(uiColor: .label)).onAppear { ids = request.ids }.interactiveDismissDisabled(false)
    }
    private func save() {
        searchFocused = false
        do {
            guard let latest = store.trips.first(where: { $0.id == request.day.tripId })?.days.first(where: { $0.id == request.day.id }), latest.chains == request.day.chains else {
                throw AppError.message("路线已更新，请关闭后重新编辑")
            }
            let updated = try RouteEditSession(day: request.day, index: request.index, ids: ids).applying(to: latest)
            guard ids.allSatisfy({ id in store.markers.contains(where: { $0.id == id }) }) else { throw AppError.message("部分地点已被删除，请重新选择") }
            if updated == latest { dismiss(); return }
            if store.saveDayInBackground(updated) { dismiss() } else { error = store.errorMessage }
        } catch { self.error = error.localizedDescription }
    }
}
struct PlaceSelectionRow: View {
    let marker: Marker
    var body: some View {
        HStack(spacing: 12) {
            MapMarkerCircle(icon: marker.icon).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(marker.title).font(.body).foregroundStyle(.primary)
                if let address = marker.content.address, !address.isEmpty {
                    Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6).contentShape(Rectangle())
    }
}
struct DayMarkerPicker: View {
    @ObservedObject var store: AppStore
    let day: TripDay?
    var compact = false
    var onExpand: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searched = false
    var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Button { store.endAddingPlace() } label: {
                        Image(systemName: "arrow.left").font(.system(size: 21, weight: .medium))
                            .frame(width: 44, height: 56).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("返回旅途")
                        .accessibilityIdentifier("close-place-picker")
                NativePlaceSearchBar(text: $store.searchText, searching: store.searching, onSearch: {
                    searched = true
                    onExpand()
                    Task { await store.search() }
                }, onClear: { store.clearSearch(); searched = false }, onBeginEditing: onExpand)
                .frame(height: 56)
                .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.top, compact ? 24 : 0)
                .padding(.bottom, compact ? 0 : 12)
                if compact { Spacer(minLength: 0) }
                if !compact {
                HStack {
                    Text(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "附近已保存地点" : "搜索结果").font(.headline)
                    Spacer()
                    if !store.searching && !store.searchResults.isEmpty {
                        Text("\(store.searchResults.count) 个地点").font(.caption).foregroundStyle(.tertiary)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 12)
                ScrollViewReader { reader in
                List {
                    if let error = store.searchError {
                        Section {
                            Text(error).foregroundStyle(.secondary)
                            Button("重试搜索") { Task { await store.search() } }
                        }
                    } else if searched && !store.searching && store.searchResults.isEmpty {
                        ContentUnavailableView.search(text: store.searchText)
                    }
                    Section {
                    ForEach(store.searchResults) { place in
                        VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 12) {
                            Button { store.choose(place, fromMap: true) } label: {
                                HStack(spacing: 12) {
                                    if let marker = store.savedMarker(for: place) {
                                        PlaceIconView(emoji: marker.icon.emoji, size: 26)
                                            .frame(width: 32, height: 32)
                                            .accessibilityHidden(true)
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                                            Text(place.name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                                            if store.savedMarker(for: place) != nil {
                                                Text("已保存")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize()
                                            }
                                        }
                                        if !place.address.isEmpty { Text(place.address).font(.footnote).foregroundStyle(.secondary).lineLimit(2) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("add-place-result-\(place.id)")
                            addButton(place)
                        }
                        }.padding(.vertical, 8).id(place.id)
                        .alignmentGuide(.listRowSeparatorLeading) { _ in 0 }
                        .listRowSeparator(.visible)
                        .listRowSeparatorTint(Color(uiColor: .separator).opacity(0.45))
                        .listRowInsets(EdgeInsets(top: 8, leading: 24, bottom: 8, trailing: 20))
                        .listRowBackground(Color(uiColor: .systemBackground))
                    }
                    SearchPaginationFooter(store: store)
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).contentMargins(.top, 0, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .overlay {
                        if store.searching && store.searchResults.isEmpty {
                            VStack(spacing: 10) {
                                ProgressView()
                                Text("搜索中…").font(.footnote).foregroundStyle(.secondary)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                                .accessibilityIdentifier("place-search-loading")
                        }
                    }
                    .accessibilityIdentifier("add-place-results")
                    .onChange(of: store.selectedSearchPlaceID) { _, id in
                        if let id { withAnimation(AppMotion.scroll(reduceMotion: reduceMotion)) { reader.scrollTo(id) } }
                    }
                }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let error = store.addPlaceError {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                }
            }
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .animation(AppMotion.presentation(reduceMotion: reduceMotion), value: compact)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $store.searchDetailPlace) { place in
                SearchPlaceDetail(store: store, place: place)
                    .onAppear {
                        store.camera = CameraCommand(points: [place.coordinates], singlePointZoom: 15, bottomSheetFraction: 0.5)
                    }
            }
            .navigationDestination(isPresented: Binding(get: { store.searchDetailPlace == nil && store.draft != nil }, set: {
                if !$0 && store.searchDetailPlace == nil { store.closeSearchDraft() }
            })) {
                if let draft = store.draft {
                    MarkerEditorView(store: store, initial: draft, embedded: true)
                        .toolbar(.visible, for: .navigationBar)
                        .id(draft.id)
                }
            }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("add-place-search-panel")
    }
    @ViewBuilder private func addButton(_ place: Place) -> some View {
        if store.savedMarker(for: place) != nil && store.addPlaceDay == nil && store.addPlaceTripID == nil {
            Button {
                Task { await store.activateSavedSearchPlace(place) }
            } label: {
                Image(systemName: "arrow.up.right").font(.system(size: 18, weight: .regular)).frame(width: 44, height: 44)
            }.buttonStyle(.borderless)
                .accessibilityLabel("查看地点：\(place.name)")
        } else if store.isPlaceAdded(place) {
            Label(day == nil ? "已保存" : "已加入", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("place-added-\(place.id)")
        } else {
            Button {
                store.choose(place); store.prepareSearchPlaceAddition(place)
            } label: {
                if store.addingPlaceID == place.id { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "plus").font(.system(size: 18, weight: .medium)).foregroundStyle(.primary).frame(width: 36, height: 36).background(Color(uiColor: .tertiarySystemFill), in: Circle()).frame(width: 44, height: 44) }
            }.buttonStyle(.plain).disabled(store.saving)
                .accessibilityLabel(store.addPlaceDay != nil ? "加入今日行程：\(place.name)" : store.addPlaceTripID != nil ? "加入当前旅行：\(place.name)" : "保存地点：\(place.name)")
                .accessibilityIdentifier("add-search-place-\(place.id)")
        }
    }
}

/// Keep in-app drag data available synchronously; loading the provider can wait
/// until after UIKit's landing animation, leaving the destination briefly empty.
final class NativePlaceItemProvider: NSItemProvider {
    let payload: String
    init(payload: String) {
        self.payload = payload
        super.init()
        suggestedName = payload
        registerObject(NSString(string: payload), visibility: .all)
    }
}

/// Attach UIKit drop handling to the native list, whose SwiftUI rows are reused.
struct NativePlaceListDrop: UIViewRepresentable {
    let frames: [String: CGRect]
    var frameSource: (() -> [String: CGRect])? = nil
    var currentFrames: [String: CGRect] { frameSource?() ?? frames }
    let prefix: String
    var onDiagnostics: (Int) -> Void = { _ in }
    var onDrop: () -> Void = {}
    var onSorting: (Bool) -> Void = { _ in }
    var sourceTargets: [String: String] = [:]
    var onTarget: (String?) -> Void = { _ in }
    let accept: (String, String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.recordViewUpdate()
        context.coordinator.parent = self
        DispatchQueue.main.async {
            var ancestor: UIView? = view
            while let current = ancestor {
                if let list = context.coordinator.findList(current) {
                    context.coordinator.attach(list); break
                }
                ancestor = current.superview
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator: NSObject, UIDropInteractionDelegate, UICollectionViewDropDelegate, UICollectionViewDragDelegate {
        var parent: NativePlaceListDrop
        weak var host: UIView?
        var dragFrames: [String: CGRect]?
        var nativeRowTargets: [IndexPath: String] = [:]
        private var publishedTarget: String?
        private var fixedFrames: [String: CGRect] = [:]
        private var cellFrames: [IndexPath: CGRect] = [:]
        private var fixedSource: IndexPath?
        private var feedbackTarget: String?
        private var feedbackOffsets: [IndexPath: CGFloat] = [:]
        private let reorderFeedback = UIImpactFeedbackGenerator(style: .medium)

        let recordsDragUpdates = ProcessInfo.processInfo.arguments.contains("--route-drag-diagnostics")
        private var diagnosticDragActive = false
        private var diagnosticUpdates = 0
        func recordViewUpdate() {
            guard recordsDragUpdates, diagnosticDragActive else { return }
            diagnosticUpdates += 1
            NSLog("ROUTEDRAG view-update-during-drag")
        }
        private func finishDiagnostics() {
            guard recordsDragUpdates else { return }
            diagnosticDragActive = false
            parent.onDiagnostics(diagnosticUpdates)
            NSLog("ROUTEDRAG finished updates=%d", diagnosticUpdates)
        }
        var interaction: UIDropInteraction?
        weak var originalDropDelegate: (any UICollectionViewDropDelegate)?
        weak var originalDragDelegate: (any UICollectionViewDragDelegate)?
        init(_ parent: NativePlaceListDrop) { self.parent = parent }
        func findList(_ view: UIView) -> UIView? {
            if view is UICollectionView || view is UITableView { return view }
            for child in view.subviews { if let found = findList(child) { return found } }
            return nil
        }
        func attach(_ view: UIView) {
            guard host !== view else { return }
            detach()
            if let list = view as? UICollectionView {
                originalDropDelegate = list.dropDelegate
                originalDragDelegate = list.dragDelegate
                list.dragDelegate = self
                list.dropDelegate = self; host = list
                return
            }
            let interaction = UIDropInteraction(delegate: self)
            view.addInteraction(interaction); host = view; self.interaction = interaction
        }
        func detach() {
            clearFixedFeedback()
            if let list = host as? UICollectionView, list.dropDelegate === self { list.dropDelegate = originalDropDelegate }
            if let list = host as? UICollectionView, list.dragDelegate === self { list.dragDelegate = originalDragDelegate }
            if let interaction { host?.removeInteraction(interaction) }
            interaction = nil; host = nil
        }
        func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
            originalDragDelegate?.collectionView(collectionView, itemsForBeginning: session, at: indexPath) ?? []
        }
        func collectionView(_ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession, at indexPath: IndexPath, point: CGPoint) -> [UIDragItem] {
            originalDragDelegate?.collectionView?(collectionView, itemsForAddingTo: session, at: indexPath, point: point) ?? []
        }
        func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
            originalDragDelegate?.collectionView?(collectionView, dragPreviewParametersForItemAt: indexPath)
        }
        func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
            originalDragDelegate?.collectionView?(collectionView, dragSessionWillBegin: session)
            if parent.prefix.hasPrefix("day-place/") { parent.onSorting(true) }
        }
        func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
            originalDragDelegate?.collectionView?(collectionView, dragSessionDidEnd: session)
            parent.onSorting(false)
        }
        func collectionView(_ collectionView: UICollectionView, dragSessionAllowsMoveOperation session: UIDragSession) -> Bool {
            originalDragDelegate?.collectionView?(collectionView, dragSessionAllowsMoveOperation: session) ?? true
        }
        func collectionView(_ collectionView: UICollectionView, dragSessionIsRestrictedToDraggingApplication session: UIDragSession) -> Bool {
            originalDragDelegate?.collectionView?(collectionView, dragSessionIsRestrictedToDraggingApplication: session) ?? true
        }
        func target(_ session: UIDropSession) -> String? {
            guard let host, let window = host.window else { return nil }
            let point = session.location(in: window)
            let frames = parent.prefix.hasPrefix("trip-place/") ? parent.currentFrames : (dragFrames ?? parent.currentFrames)
            if parent.prefix.hasPrefix("day-place/"),
               host.bounds.contains(session.location(in: host)),
               let pool = frames["unplanned"], point.y >= pool.minY {
                return "unplanned"
            }
            guard let match = frames.sorted(by: { $0.key.split(separator: "/").count > $1.key.split(separator: "/").count }).first(where: { $0.value.contains(point) }) else { return nil }
            let parts = match.key.split(separator: "/")
            if parts.count == 2, Int(parts[1]) != nil {
                return match.key + (point.y < match.value.midY ? "/before" : "/after")
            }
            return match.key
        }
        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            if dragFrames == nil {
                diagnosticDragActive = true; diagnosticUpdates = 0
                reorderFeedback.prepare()
                dragFrames = parent.currentFrames
                cellFrames = Dictionary(uniqueKeysWithValues: collectionView.indexPathsForVisibleItems.compactMap { path in
                    collectionView.cellForItem(at: path).map { (path, $0.frame) }
                })
                nativeRowTargets = [:]
                if let window = collectionView.window {
                    if let pool = parent.currentFrames["unplanned"] {
                        for path in collectionView.indexPathsForVisibleItems {
                            if let cell = collectionView.cellForItem(at: path) {
                                let point = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window)
                                if pool.contains(point) { nativeRowTargets[path] = "unplanned" }
                            }
                        }
                    }
                    for (key, frame) in parent.currentFrames where key != "unplanned" && !key.hasPrefix("source/") {
                        let point = collectionView.convert(CGPoint(x: frame.midX, y: frame.midY), from: window)
                        if let path = collectionView.indexPathForItem(at: point) { nativeRowTargets[path] = key }
                    }
                }
            }
            if fixedFrames.isEmpty {
                for (path, key) in nativeRowTargets {
                    if let frame = cellFrames[path] { fixedFrames[key] = fixedFrames[key].map { $0.union(frame) } ?? frame }
                }
                if let payload = localPayload(session) {
                    let parts = payload.dropFirst(parent.prefix.count).split(separator: "/")
                    if parts.count == 2, let key = parent.sourceTargets[String(parts[0]) + "/" + String(parts[1])] {
                        fixedSource = nativeRowTargets.first { $0.value == key }?.key
                    } else if let marker = parts.first, let window = collectionView.window,
                              let frame = parent.currentFrames["source/" + String(marker)] {
                        let point = collectionView.convert(CGPoint(x: frame.midX, y: frame.midY), from: window)
                        fixedSource = collectionView.indexPathForItem(at: point)
                    }
                }
            }
            return session.localDragSession != nil && session.canLoadObjects(ofClass: NSString.self)
        }
        /// The List keeps collapsed schedule/transport cells at their old height while
        /// a drag is active, so sorting removes that space visually for every later row.
        private var compactShifts: [IndexPath: CGFloat] = [:]
        private var compactFrames: [IndexPath: CGRect] {
            cellFrames.reduce(into: [:]) { result, entry in
                result[entry.key] = entry.value.offsetBy(dx: 0, dy: compactShifts[entry.key] ?? 0)
            }
        }
        private func updateCompactShifts() {
            let routeSections = Set(nativeRowTargets.compactMap { path, key in
                key == "unplanned" || key.hasPrefix("source/") ? nil : path.section
            })
            var removed: CGFloat = 0
            compactShifts = [:]
            for path in cellFrames.keys.sorted() {
                compactShifts[path] = -removed
                if routeSections.contains(path.section), nativeRowTargets[path] == nil, path != fixedSource {
                    removed += cellFrames[path]?.height ?? 0
                }
            }
        }
        private func fixedTarget(_ session: UIDropSession) -> String? {
            guard let list = host as? UICollectionView else { return nil }
            // Keep stable row identities, but follow their shrinking layout and scrolling.
            for path in Array(cellFrames.keys) {
                if let attributes = list.layoutAttributesForItem(at: path) { cellFrames[path] = attributes.frame }
            }
            updateCompactShifts()
            fixedFrames = [:]
            for (path, key) in nativeRowTargets {
                if let frame = compactFrames[path] { fixedFrames[key] = fixedFrames[key].map { $0.union(frame) } ?? frame }
            }
            let point = session.location(in: list)
            guard list.bounds.contains(point) else { return nil }
            return NativeRouteDropGeometry.target(at: point, frames: fixedFrames)
        }
        private func updateFixedFeedback(_ target: String?, list: UICollectionView) {
            let targetChanged = feedbackTarget != target
            feedbackTarget = target
            var offsets: [IndexPath: CGFloat] = [:]
            let cellFrames = compactFrames
            if let target, let route = target.split(separator: "/").first, Int(route) != nil {
                let rows = nativeRowTargets.filter { _, key in
                    let parts = key.split(separator: "/")
                    return parts.count == 2 && parts.first == route && Int(parts[1]) != nil
                }.keys.sorted()
                let parts = target.split(separator: "/")
                let boundary = (parts.count > 1 ? Int(parts[1]) : nil).map { $0 + (parts.last == "after" ? 1 : 0) }
                    ?? rows.compactMap { nativeRowTargets[$0]?.split(separator: "/").last.flatMap { Int($0) } }.map { $0 + 1 }.max() ?? 0
                let sourceHeight = fixedSource.flatMap { cellFrames[$0]?.height } ?? 44
                if let source = fixedSource, rows.contains(source) {
                    var order = rows.filter { $0 != source }
                    let insertion = order.filter { path in
                        Int(nativeRowTargets[path]?.split(separator: "/").last ?? "") ?? 0 < boundary
                    }.count
                    order.insert(source, at: insertion)
                    var top = rows.compactMap { cellFrames[$0]?.minY }.min() ?? 0
                    for path in order {
                        guard let frame = cellFrames[path] else { continue }
                        if path != source { offsets[path] = top - frame.minY }
                        top += frame.height
                    }
                } else {
                    // Incoming pool/cross-route place uses the very same frozen
                    // insertion boundary. Only the space needed by the source differs.
                    let insertionY = rows.first { path in
                        (Int(nativeRowTargets[path]?.split(separator: "/").last ?? "") ?? 0) >= boundary
                    }.flatMap { cellFrames[$0]?.minY } ?? rows.compactMap { cellFrames[$0]?.maxY }.max()
                    if let source = fixedSource, let sourceFrame = cellFrames[source], let insertionY {
                        for (path, frame) in cellFrames where path != source {
                            if sourceFrame.minY >= insertionY, frame.minY >= insertionY, frame.minY < sourceFrame.minY {
                                offsets[path] = sourceHeight
                            } else if sourceFrame.minY < insertionY, frame.minY > sourceFrame.minY, frame.minY < insertionY {
                                offsets[path] = -sourceHeight
                            }
                        }
                    } else {
                        for path in rows {
                            let ordinal = Int(nativeRowTargets[path]?.split(separator: "/").last ?? "") ?? 0
                            if ordinal >= boundary { offsets[path] = sourceHeight }
                        }
                    }
                }
            }
            let changedOffsets = offsets.filter { abs($0.value) > 0.5 }
            for (path, shift) in compactShifts { offsets[path, default: 0] += shift }
            let offsetsChanged = changedOffsets != feedbackOffsets
            if target != nil, offsetsChanged {
                reorderFeedback.impactOccurred()
                reorderFeedback.prepare()
            }
            feedbackOffsets = changedOffsets
            let animations = {
                for path in list.indexPathsForVisibleItems where path != self.fixedSource {
                    list.cellForItem(at: path)?.transform = CGAffineTransform(translationX: 0, y: offsets[path] ?? 0)
                }
            }
            // Self-sizing passes reapply layout attributes and reset cell transforms.
            if !targetChanged && !offsetsChanged {
                let stale = list.indexPathsForVisibleItems.contains { path in
                    guard path != fixedSource, let cell = list.cellForItem(at: path) else { return false }
                    return abs(cell.transform.ty - (offsets[path] ?? 0)) > 0.5
                }
                if stale { UIView.performWithoutAnimation(animations) }
                return
            }
            if UIAccessibility.isReduceMotionEnabled { animations() }
            else { UIView.animate(withDuration: 0.18, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: animations) }
        }
        private func clearFixedFeedback() {
            if let list = host as? UICollectionView {
                for cell in list.visibleCells { cell.layer.removeAllAnimations(); cell.transform = .identity }
            }
            feedbackTarget = nil; feedbackOffsets = [:]
        }
        private func resolvedTarget(_ session: UIDropSession, destination: IndexPath?) -> String? {
            if parent.prefix.hasPrefix("day-place/"), host is UICollectionView { return fixedTarget(session) }
            return target(session)
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            let target = resolvedTarget(session, destination: destinationIndexPath)
            if recordsDragUpdates, feedbackTarget != target { NSLog("ROUTEDRAG boundary=%@ source=%@", target ?? "nil", fixedSource?.description ?? "nil") }
            publishTarget(target)
            if parent.prefix.hasPrefix("day-place/") {
                updateFixedFeedback(target, list: collectionView)
                return UICollectionViewDropProposal(operation: target == nil ? .cancel : .move, intent: .unspecified)
            }
            return UICollectionViewDropProposal(operation: target == nil ? .cancel : .move, intent: .insertIntoDestinationIndexPath)
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            parent.onSorting(false)
            clearFixedFeedback(); fixedFrames = [:]; cellFrames = [:]; compactShifts = [:]; fixedSource = nil
            finishDiagnostics()
            originalDropDelegate?.collectionView?(collectionView, dropSessionDidEnd: session)
            publishTarget(nil); dragFrames = nil; nativeRowTargets = [:]
        }
        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            finishDiagnostics()
            guard let target = resolvedTarget(coordinator.session, destination: coordinator.destinationIndexPath) else { return }
            clearFixedFeedback()
            publishTarget(nil)
            acceptDrop(coordinator.session, target: target)
            parent.onSorting(false)
            // The native lifted snapshot contains the old ordinal. A day move
            // commits the actual row synchronously; do not keep that frozen image
            // over it with a second landing animation.
            if !parent.prefix.hasPrefix("day-place/"),
               let destination = coordinator.destinationIndexPath,
               let attributes = collectionView.layoutAttributesForItem(at: destination) {
                for item in coordinator.items {
                    coordinator.drop(item.dragItem, to: UIDragPreviewTarget(container: collectionView, center: attributes.center))
                }
            }

        }
        func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
            session.localDragSession != nil && session.canLoadObjects(ofClass: NSString.self)
        }
        private func publishTarget(_ target: String?) {
            guard publishedTarget != target else { return }
            publishedTarget = target
            DispatchQueue.main.async { self.parent.onTarget(target) }
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession) {
            clearFixedFeedback()
            publishTarget(nil)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
            let target = resolvedTarget(session, destination: nil)
            publishTarget(target)
            return UIDropProposal(operation: target == nil ? .cancel : .move)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
            publishTarget(nil)
        }
        func dropInteraction(_ interaction: UIDropInteraction, sessionDidEnd session: UIDropSession) {
            publishTarget(nil)
        }
        func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
            guard let target = publishedTarget else { return }
            publishTarget(nil)
            acceptDrop(session, target: target)
        }
        private func localPayload(_ session: UIDropSession) -> String? {
            guard session.localDragSession != nil, let item = session.items.first else { return nil }
            let payload = (item.localObject as? String)
                ?? (item.itemProvider as? NativePlaceItemProvider)?.payload
                ?? item.itemProvider.suggestedName
            guard let payload, payload.hasPrefix(parent.prefix) else { return nil }
            return payload
        }
        private func acceptDrop(_ session: UIDropSession, target: String) {
            parent.onDrop()
            let prefix = parent.prefix, accept = parent.accept
            if let payload = localPayload(session) {
                accept(String(payload.dropFirst(prefix.count)), target)
                return
            }
            session.loadObjects(ofClass: NSString.self) { objects in
                guard let text = objects.first as? String, text.hasPrefix(prefix) else { return }
                accept(String(text.dropFirst(prefix.count)), target)
            }
        }
    }
}
/// Layout measurements feed drop hit-testing, not SwiftUI rendering. Native
/// reordering changes these every animation frame; publishing them as @State
/// invalidates the List while UIKit is in the middle of moving its own cells.
private final class NativeRouteGeometryStorage {
    var frames: [String: CGRect] = [:]
}

private struct NativeRouteFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}

/// Horizontal card margins are valid too. Within a route, every vertical gap
/// belongs to its nearest visit boundary; only the header appends to the end.
enum NativeRouteDropGeometry {
    static func target(at point: CGPoint, frames: [String: CGRect]) -> String? {
        // The caller bounds this to the list viewport; blank space below the pool is valid too.
        if let pool = frames["unplanned"], point.y >= pool.minY { return "unplanned" }
        let routes = Set(frames.keys.compactMap { Int($0.split(separator: "/").first ?? "") })
        for route in routes.sorted() {
            let prefix = String(route) + "/"
            let entries = frames.filter { $0.key.hasPrefix(prefix) }
            guard let top = entries.values.map(\.minY).min(), let bottom = entries.values.map(\.maxY).max(),
                  point.y >= top - 8, point.y <= bottom + 8 else { continue }
            if let header = entries[prefix + "header"], point.y <= header.maxY { return prefix + "header" }
            let rows = entries.compactMap { key, frame -> (Int, CGRect)? in
                guard let position = Int(key.dropFirst(prefix.count)) else { return nil }
                return (position, frame)
            }.sorted { $0.0 < $1.0 }
            for (position, frame) in rows {
                if point.y < frame.midY { return prefix + String(position) + "/before" }
            }
            if let last = rows.last { return prefix + String(last.0) + "/after" }
            return prefix + "header"
        }
        return nil
    }
}


struct SearchPlaceDetail: View {
    @ObservedObject var store: AppStore
    let place: Place
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    private var marker: Marker? { store.savedMarker(for: place) }
    var body: some View {
        Group {
            if let marker {
                MarkerDetailView(store: store, marker: marker, edgeAttached: true, embedded: true, searchPlace: place,
                    onClose: close, onNavigateItinerary: { store.endAddingPlace() })
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("search-place-detail")
            } else { unsavedContent }
        }
    }
    private func close() {
        withAnimation(AppMotion.crossfade(reduceMotion: UIAccessibility.isReduceMotionEnabled)) { store.searchDetailPlace = nil }
    }
    private var categoryColor: Color {
        MarkerIcon.allCases.first(where: { $0.label == place.categoryLabel })?.themeColor ?? Color(uiColor: .secondaryLabel)
    }
    private var unsavedContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        Text(place.name).font(.title.bold()).frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                            .accessibilityLabel("关闭地点详情").accessibilityIdentifier("search-detail-back")
                    }
                    HStack(spacing: 10) {
                        if let category = place.categoryLabel {
                            Text(category).font(.caption.weight(.medium))
                                .foregroundStyle(categoryColor).padding(.horizontal, 8).padding(.vertical, 4)
                                .background(categoryColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                        }
                        if let rating = place.rating, rating > 0 {
                            Label(rating.formatted(.number.precision(.fractionLength(1))), systemImage: "star")
                                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        }
                    }
                    if !place.address.isEmpty {
                        Text(place.address).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let phone = place.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: -20) {
            HStack(spacing: 12) {
                if store.isPlaceAdded(place) {
                    Label(store.addPlaceDay != nil || store.addPlaceTripID != nil ? "已加入" : "已保存", systemImage: "checkmark").font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Button {
                        store.prepareSearchPlaceAddition(place)
                    } label: {
                        Label(store.addPlaceDay != nil ? "加入当天" : store.addPlaceTripID != nil ? "加入旅行" : "保存地点", systemImage: "plus")
                    }.disabled(store.saving).accessibilityIdentifier("search-detail-add")
                }
                Button {
                    var url = URLComponents(string: "https://maps.apple.com/")!
                    url.queryItems = [URLQueryItem(name: "daddr", value: "\(place.coordinates.latitude),\(place.coordinates.longitude)"), URLQueryItem(name: "q", value: place.name)]
                    if let url = url.url { openURL(url) }
                } label: { Label("导航", systemImage: "location") }
                Spacer(minLength: 0)
            }.buttonStyle(JourneyActionStyle(compact: true))
                .padding(.horizontal, 16).padding(.top, 24).padding(.bottom, 10)
                .background {
                    LinearGradient(stops: [.init(color: Color(uiColor: .systemBackground).opacity(0), location: 0),
                        .init(color: Color(uiColor: .systemBackground), location: 0.3),
                        .init(color: Color(uiColor: .systemBackground), location: 1)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom).allowsHitTesting(false)
                }
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(isPresented: Binding(get: { store.draft != nil }, set: { if !$0 { store.draft = nil; store.editingSearchPlaceID = nil } })) {
            if let draft = store.draft {
                MarkerEditorView(store: store, initial: draft, embedded: true)
                    .toolbar(.visible, for: .navigationBar)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("search-place-detail")
    }
}

struct DayPlaceTransferRequest: Identifiable {
    let id = UUID()
    let source: TripDay
    let ids: Set<String>
    var references: Set<DayPlaceReference>? = nil
    let copy: Bool
}
struct DayPlaceTransferPicker: View {
    @ObservedObject var store: AppStore
    let request: DayPlaceTransferRequest
    let onCancel: () -> Void
    let onSubmitted: () -> Void
    @State private var destinationID: String?
    private var days: [TripDay] {
        store.trips.first(where: { $0.id == request.source.tripId })?.days.sorted { $0.date < $1.date } ?? []
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .center) {
                        JourneyEditorHeading(title: "选择日期")
                        Spacer()
                        Button(action: onCancel) { Image(systemName: "xmark").font(.body).frame(width: 44, height: 44) }
                            .buttonStyle(.plain).accessibilityLabel("取消").accessibilityIdentifier("transfer-day-cancel")
                    }
                    Text("\(request.ids.count) 个地点 · \(request.copy ? "保留原日期的安排" : "移出原日期的安排")")
                        .font(.footnote).foregroundStyle(.secondary)
                    if days.count < 2 {
                        Text("旅途只有一天，延长旅途后可选择其他日期。")
                            .font(.body).foregroundStyle(.secondary)
                    }
                    ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                        if day.id != request.source.id {
                            Button { destinationID = day.id } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: destinationID == day.id ? "checkmark.circle.fill" : "circle")
                                        .font(.title2).foregroundStyle(destinationID == day.id ? Color(uiColor: .label) : Color(uiColor: .tertiaryLabel))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text("第\(index + 1)天 · \(JourneyDayCardContent.dateFormatter.string(from: Date.fromDay(day.date)))")
                                            .font(.body.weight(.medium))
                                        if let title = day.title, !title.isEmpty { Text(title).font(.footnote).foregroundStyle(.secondary) }
                                    }
                                    Spacer()
                                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color(uiColor: .separator))
                                            .frame(height: 1 / UIScreen.main.scale)
                                            .allowsHitTesting(false)
                                    }
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("transfer-day-" + day.id)
                                .accessibilityValue(destinationID == day.id ? "已选择" : "未选择")
                        }
                    }
                }.padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                JourneyEditorSubmit(title: request.copy ? "复制到这一天" : "移动到这一天",
                    enabled: destinationID != nil && store.canEditItinerary, identifier: "transfer-day-submit", background: Color(uiColor: .systemBackground)) {
                    guard let destination = days.first(where: { $0.id == destinationID }) else { return }
                    if store.transferDayPlaces(request.ids, from: request.source, to: destination, copy: request.copy, references: request.references) {
                        onSubmitted()
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }.tint(Color(uiColor: .label))
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}

private struct ArrangementDuringSorting: ViewModifier {
    let collapsed: Bool
    func body(content: Content) -> some View {
        content
            .frame(height: collapsed ? 0 : nil, alignment: .top)
            .opacity(collapsed ? 0 : 1)
            .clipped()
            .allowsHitTesting(!collapsed)
            .accessibilityHidden(collapsed)
    }
}

private struct DayPlaceEditingDrag: ViewModifier {
    let enabled: Bool
    let payload: String
    func body(content: Content) -> some View {
        if enabled { content.onDrag { NativePlaceItemProvider(payload: payload) } }
        else { content }
    }
}

private struct EditingDistanceSnapshot: Equatable {
    let day: TripDay
    let markers: [Marker]
    let server: String
    let planning: Bool
    let provider: MapServiceProvider
}

private struct DayEditingWorkspace: View {
    @ObservedObject var store: AppStore
    let tripID: String
    let dayID: String
    @Environment(\.dismiss) private var dismiss
    @State private var editing = true
    var body: some View {
        NavigationStack {
            if let day = store.trips.first(where: { $0.id == tripID })?.days.first(where: { $0.id == dayID }) {
                DayContentsView(store: store, day: day, showsDaySummary: true, showsEditingDone: false,
                    isEditingWorkspace: true, editingPlaces: $editing)
                    .listStyle(.insetGrouped).scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemBackground))
                    .navigationTitle("编辑行程").navigationBarTitleDisplayMode(.inline)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let trip = store.trips.first(where: { $0.id == tripID }) {
                            editingDates(trip: trip, day: day)
                        }
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { dismiss() }.accessibilityIdentifier("day-edit-done")
                        }.journeyBareBackground

                    }
            }
        }.onChange(of: editing) { _, value in if !value { dismiss() } }
    }
    private func editingDates(trip: Trip, day: TripDay) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, date in
                        VStack(spacing: 5) {
                            Text("第 \(index + 1) 天").font(.caption).foregroundStyle(.secondary)
                            Text(Date.fromDay(date.date), format: .dateTime.month(.defaultDigits).day())
                                .font(.body).monospacedDigit()
                            Capsule().fill(date.id == day.id ? Color.primary : .clear).frame(width: 40, height: 3)
                        }.foregroundStyle(date.id == day.id ? .primary : .secondary)
                            .frame(width: 84).padding(.vertical, 12).id(date.id)
                            .accessibilityIdentifier("edit-day-date-\(date.id)")
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
                .onAppear { proxy.scrollTo(day.id, anchor: .center) }
        }.background(Color(uiColor: .systemBackground))
            .overlay(alignment: .top) { Divider() }
            .overlay(alignment: .bottom) { Divider() }
    }
}
