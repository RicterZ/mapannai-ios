import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct JourneyDaysContents: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    var onSelectDay: ((TripDay) -> Void)? = nil
    var archiveColorIndex: Int? = nil
    var archiveHeaderVisible = true
    var archivePhoto: UIImage? = nil
    var onArchiveHeaderFrame: (CGRect) -> Void = { _ in }
    private var unscheduledPlaces: [Marker] {
        if store.tripPlacesPreview { return store.previewTripPlaces[trip.id] ?? [] }
        let ids = Set(trip.markerIds ?? [])
        return store.markers.filter { ids.contains($0.id) }
    }
    @State private var nativeDayFrames: [String: CGRect] = [:]
    @State private var targetedDayID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var deletion: TripDay?
    var body: some View {
        let days = trip.days.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        let cover = archiveColorIndex == nil ? nil : JourneyDaySummary.cover(trip: trip, markers: store.markers)
        let summaries = JourneyDaySummary.chapters(days: days, markers: store.markers,
            excludingPhotos: Set([cover].compactMap { $0 }))
        List {
            if let archiveColorIndex {
                Section {
                    JourneyArchiveCard(trip: trip, colorIndex: archiveColorIndex, photo: archivePhoto)
                        .frame(height: 204)
                        .opacity(archiveHeaderVisible ? 1 : 0)
                        // The snapshot owns motion; the live header must hand off without a cross-fade.
                        .transaction { transaction in
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                        .accessibilityIdentifier("archive-detail-card")
                        .id("archive-header")
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ArchiveHeaderFrame.self,
                                value: proxy.frame(in: .global))
                        })
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            Group {

            ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                Section {
                ZStack(alignment: .topTrailing) {
                Button {
                    if let onSelectDay { onSelectDay(day) }
                    else { store.select(trip: trip, day: day); store.beginDayMapBrowsing() }
                } label: {
                    dayRow(day, index: index, summary: summaries[index])
                        .contentShape(Rectangle())
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NativeDayFrames.self, value: [day.id: geometry.frame(in: .global)])
                        })
                }.buttonStyle(.plain).disabled(day.id.hasPrefix("pending-day-"))
                    .accessibilityIdentifier("journey-day-\(day.id)")
                    .contextMenu { dayActions(day) }
                Menu { dayActions(day) } label: {
                    Image(systemName: "ellipsis").font(.body.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("第\(index + 1)天的操作")
                .accessibilityIdentifier("journey-day-menu-\(day.id)")
                }

                    .listRowInsets(EdgeInsets(top: 16, leading: 4, bottom: 16, trailing: 4))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color(uiColor: .tertiarySystemFill).opacity(targetedDayID == day.id ? 1 : 0))
                    .animation(reduceMotion ? nil : .default, value: targetedDayID == day.id)
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { store.beginDayEditor(trip: trip, day: day) } label: { Image(systemName: "pencil") }
                            .accessibilityLabel("编辑").tint(.blue).disabled(store.saving)
                    }


                }
            }
            if !unscheduledPlaces.isEmpty {
                Section {
                    JourneyPlaceGroupHeading(title: "未安排日期", count: unscheduledPlaces.count)
                    ForEach(unscheduledPlaces) { marker in
                        DayPlaceIdentity(marker: marker)
                            .listRowBackground(Color(uiColor: .systemBackground))
                            .listRowSeparator(.hidden)
                            .contentShape(Rectangle())
                            .onTapGesture { store.focus(marker) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("trip-unscheduled-\(marker.id)")
                            .onDrag {
                                guard !store.saving else { return NSItemProvider() }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                return NativePlaceItemProvider(payload: "trip-place/" + trip.id + "/" + marker.id)
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button {
                                    if store.tripPlacesPreview { store.previewTripPlaces[trip.id]?.removeAll { $0.id == marker.id } }
                                    else { _ = store.removeTripPlaceInBackground(marker.id, from: trip.id) }
                                } label: { Image(systemName: "minus.circle") }
                                .tint(.red).accessibilityLabel("从旅行移除").disabled(store.saving)
                            }
                    }
                }
            }
            Section {
                JourneyActionGroup(compact: true) {
                    if !unscheduledPlaces.isEmpty || !store.demo {
                        Button { store.beginAddingPlace(tripID: trip.id) } label: {
                            Label("添加地点", systemImage: "plus")
                        }.accessibilityIdentifier("trip-add-place")
                    }
                    Button { store.beginDayEditor(trip: trip) } label: { Label("添加一天", systemImage: "plus") }
                        .disabled(store.saving)
                        .accessibilityIdentifier("journey-add-day")
                    Button { editing = true } label: {
                        Label("编辑旅途", systemImage: "pencil")
                    }
                        .disabled(store.saving).accessibilityIdentifier("journey-edit-trip")
                }.listRowBackground(Color.clear).listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }
            }
        }
            .onPreferenceChange(ArchiveHeaderFrame.self) { if !$0.isEmpty { onArchiveHeaderFrame($0) } }
            .scrollContentBackground(.hidden)
            .background(Color(uiColor: .systemBackground))
            .listSectionSpacing(8)
            .onPreferenceChange(NativeDayFrames.self) { nativeDayFrames = $0 }
            .sensoryFeedback(.selection, trigger: targetedDayID) { _, newValue in newValue != nil }
            .background(NativePlaceListDrop(frames: nativeDayFrames, prefix: "trip-place/" + trip.id + "/", onTarget: { targetedDayID = $0 }) { id, dayID in
                if let day = trip.days.first(where: { $0.id == dayID }) {
                    _ = assignPreviewPlaces(["trip-place/" + trip.id + "/" + id], to: day)
                }
            })
            .fullScreenCover(isPresented: $editing) { TripEditorView(store: store, trip: trip).presentationDragIndicator(.visible) }
            .sheet(item: Binding(get: { archiveColorIndex != nil && store.dayEditorDraft?.tripID == trip.id ? store.dayEditorDraft : nil },
                set: { if $0 == nil, archiveColorIndex != nil, store.dayEditorDraft?.tripID == trip.id { store.dayEditorDraft = nil } })) { draft in
                JourneyDayEditor(store: store, draft: draft)
            }
            .sheet(item: $deletion) { day in
                DayDeletionView(store: store, day: day)
            }
    }
    @ViewBuilder private func dayActions(_ day: TripDay) -> some View {
        Button("编辑", systemImage: "pencil") {
            store.beginDayEditor(trip: trip, day: day)
        }.disabled(store.saving)
        DestructiveMenuButton(title: "删除", systemImage: "trash") { deletion = day }
            .disabled(trip.days.count <= 1 || store.saving)
    }

    /// The day membership endpoint atomically removes the trip-only membership.
    private func assignPreviewPlaces(_ payloads: [String], to day: TripDay) -> Bool {
        let prefix = "trip-place/" + trip.id + "/"
        let ids = Set(payloads.filter { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) })
        let places = unscheduledPlaces.filter { ids.contains($0.id) }
        guard !places.isEmpty,
              let ti = store.trips.firstIndex(where: { $0.id == trip.id }),
              let di = store.trips[ti].days.firstIndex(where: { $0.id == day.id }) else { return false }
        if !store.tripPlacesPreview {
            guard places.count == 1 else { return false }
            return store.addMarkerInBackground(places[0], to: day)
        }
        withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) {
            for marker in places {
                if !store.markers.contains(where: { $0.id == marker.id }) { store.markers.append(marker) }
                if !store.trips[ti].days[di].markerIds.contains(marker.id) {
                    store.trips[ti].days[di].markerIds.append(marker.id)
                }
            }
            store.previewTripPlaces[trip.id]?.removeAll { ids.contains($0.id) }
        }
        store.rebuildRoutes(preservingPlannedGeometry: true)
        return true
    }

    private func dayRow(_ day: TripDay, index: Int, summary: JourneyDaySummary) -> some View {
        JourneyDayCardContent(day: day, index: index, summary: summary,
            loadPhotos: archiveColorIndex == nil || archiveHeaderVisible)
            .contentShape(Rectangle())
    }

}

private struct NativeDayFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $0.union($1) })
    }
}

struct JourneyArchiveView: View {
    @ObservedObject var store: AppStore
    @Binding var path: [JourneyDestination]
    let mapVisible: Bool
    var onOpenSettings: () -> Void
    var onSelect: (Trip, TripDay?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var openedID: String?
    @State private var openingFrame = CGRect.zero
    @State private var openingIndex = 0
    @State private var slotViewportHeight: CGFloat?
    @State private var detailVisible = false
    @State private var cardInList = false
    @State private var closing = false
    @State private var transitionStarted = false
    @State private var destinationFrame = CGRect.zero
    @State private var headerGeometry = ArchiveHeaderGeometry()
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var transferCards: [ArchiveTransferCard] = []
    @State private var dividerFrames: [Int: CGRect] = [:]
    @State private var transferDividers: [ArchiveTransferDivider] = []
    @State private var photos: [URL: UIImage] = [:]
    @State private var creating = false
    @State private var editing: Trip?
    @State private var deleting: Trip?
    @State private var independentDetail: Marker?

    private var openedTrip: Trip? { trips.first { $0.id == openedID } }
    private var independent: [Marker] {
        let assigned = Set(store.trips.flatMap { ($0.markerIds ?? []) + $0.days.flatMap(\.markerIds) })
        return store.markers.filter { !assigned.contains($0.id) }
    }
    private var trips: [Trip] {
        JourneyArchiveOrdering.sorted(store.trips, today: Date.now.dayString)
    }
    private var photoURLs: [URL] {
        var urls: [URL] = []
        for trip in trips {
            if let url = JourneyDaySummary.cover(trip: trip, markers: store.markers) { urls.append(url) }
            let days = trip.days.sorted { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
            urls.append(contentsOf: JourneyDaySummary.chapters(days: days, markers: store.markers).compactMap(\.coverURL))
        }
        return Array(Set(urls))
    }
    private func coverPhoto(_ trip: Trip) -> UIImage? {
        JourneyDaySummary.cover(trip: trip, markers: store.markers).flatMap { photos[$0] }
    }
    private var yearGroups: [Int: JourneyArchiveYearGroup] {
        JourneyArchiveOrdering.yearGroups(trips, today: Date.now.dayString)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                archive(height: slotViewportHeight ?? geometry.size.height)
                    .allowsHitTesting(openedID == nil)
                    .accessibilityHidden(openedID != nil)
                if let trip = openedTrip {
                    ZStack(alignment: .topLeading) {
                        JourneyDaysContents(store: store, trip: trip, onSelectDay: { onSelect(trip, $0) }, archiveColorIndex: openingIndex,
                            archiveHeaderVisible: cardInList,
                            archivePhoto: coverPhoto(trip) ?? transferCards.first { $0.id == trip.id }?.photo,
                            onArchiveHeaderFrame: {
                                let origin = geometry.frame(in: .global).origin
                                headerGeometry.frame = $0.offsetBy(dx: -origin.x, dy: -origin.y)
                            })
                            .id(trip.id)
                            .listStyle(.insetGrouped)
                            .contentMargins(.top, 16, for: .scrollContent)
                            .scrollClipDisabled()
                            .modifier(ArchiveDetailScrollEdges())
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: 640).frame(maxWidth: .infinity)
                            .opacity(cardInList ? 1 : 0)
                            .transaction { $0.animation = nil; $0.disablesAnimations = true }
                            .allowsHitTesting(cardInList)
                            .zIndex(Double(openingIndex))
                            .task(id: trip.id) { await beginTransition(trip) }
                        if transitionStarted {
                            ArchiveCardTransition(cards: transferCards, dividers: transferDividers, selectedID: trip.id,
                                destination: destinationFrame, height: slotViewportHeight ?? geometry.size.height,
                                expanded: detailVisible, handedOff: cardInList, reduceMotion: reduceMotion) {
                                    if detailVisible && !closing {
                                        cardInList = true
                                        store.select(trip: trip, focus: false)
                                    } else if closing {
                                        var transaction = Transaction(); transaction.disablesAnimations = true
                                        withTransaction(transaction) {
                                            transitionStarted = false
                                            openedID = nil
                                            slotViewportHeight = nil
                                            closing = false
                                        }
                                    }
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .allowsHitTesting(false)
                                .accessibilityHidden(true)
                                .zIndex(100)
                        }
                    }
                    .zIndex(100)
                }
            }
            .coordinateSpace(name: "journey-archive")
            .mask(alignment: .top) {
                Rectangle().ignoresSafeArea(.container)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if openedID == nil {
                Button { creating = true } label: {
                    Image(systemName: "plus").font(.system(size: 23, weight: .regular))
                        .frame(width: 52, height: 52)
                        .background(.regularMaterial, in: Circle())
                        .overlay { Circle().strokeBorder(Color(uiColor: .separator).opacity(0.15), lineWidth: 0.5) }
                        .shadow(color: .black.opacity(0.10), radius: 8, y: 3)
                        .contentShape(Circle())
                }.buttonStyle(.plain).accessibilityLabel("创建旅行").accessibilityIdentifier("archive-create")
                    .padding(.trailing, 24).padding(.bottom, 16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Visibility.hidden, for: .navigationBar)
        .tint(Color(uiColor: .label))
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Group {
                    if openedID != nil && !closing {
                        Button(action: close) {
                            Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
                                .foregroundStyle(Color(uiColor: .label))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .contentShape(Circle())
                        }.accessibilityLabel("关闭旅途详情")
                            .accessibilityIdentifier("archive-detail-close").buttonStyle(.plain)
                    } else {
                        // Preserve navigation geometry without leaving a hidden UIKit button.
                        Color.clear.frame(width: 44, height: 44).allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.transaction { $0.animation = nil }
            }.journeyBareBackground
        }
        .task(id: photoURLs) {
            let urls = photoURLs
            for url in urls where photos[url] == nil {
                let image = await JourneyPhotoCache.shared.image(for: url)
                guard !Task.isCancelled else { return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { photos[url] = image }
            }
            photos = photos.filter { urls.contains($0.key) }
        }
        .onPreferenceChange(ArchiveCardFrames.self) { if openedID == nil { cardFrames = $0 } }
        .onPreferenceChange(ArchiveDividerFrames.self) { if openedID == nil { dividerFrames = $0 } }
        .onAppear { if let trip = openedTrip { store.select(trip: trip, focus: false) } }
        .onChange(of: path) { _, value in
            if value.isEmpty, let trip = openedTrip { store.select(trip: trip, focus: false) }
        }
        .onChange(of: store.selectedMarker?.id) { _, id in
            if id != nil, !mapVisible, independentDetail == nil, let trip = openedTrip { onSelect(trip, store.day) }
        }
        .onChange(of: trips.map(\.id)) { _, ids in
            if let openedID, !ids.contains(openedID) { close() }
        }
        .sheet(item: $independentDetail, onDismiss: { store.selectedMarker = nil }) { marker in
            MarkerDetailView(store: store, marker: marker, onClose: { independentDetail = nil }, onNavigateItinerary: {
                if let trip = store.trip {
                    let day = store.day
                    independentDetail = nil
                    onSelect(trip, day)
                }
            })
        }
        .fullScreenCover(isPresented: $creating) { TripEditorView(store: store, trip: nil) }
        .fullScreenCover(item: $editing) { TripEditorView(store: store, trip: $0) }
        .sheet(item: $deleting) { TripDeletionView(store: store, trip: $0) }
        .fullScreenCover(item: Binding(get: { mapVisible || store.tripSaveRecovery?.trip == nil ? nil : store.tripSaveRecovery }, set: { if !mapVisible { store.tripSaveRecovery = $0 } })) { draft in
            TripEditorView(store: store, trip: draft.trip, initial: draft)
        }
        .fullScreenCover(item: Binding(get: { !mapVisible && store.tripSaveRecovery?.trip == nil ? store.tripSaveRecovery : nil }, set: { if !mapVisible { store.tripSaveRecovery = $0 } })) { draft in
            TripCreationView(store: store, initial: draft)
        }
        .journeyError(store: store, enabled: !mapVisible && store.dayEditorDraft == nil)
    }

    private func archive(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("我的旅途").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("archive-page-title")
                        Spacer()
                        Button(action: onOpenSettings) {
                            Image(systemName: "gearshape").font(.system(size: 20))
                                .frame(width: 44, height: 44)
                                .background(.regularMaterial, in: Circle())
                                .contentShape(Circle())
                        }.buttonStyle(.plain).accessibilityLabel("设置")
                            .accessibilityIdentifier("archive-settings")
                    }
                    Text("旅の目的地は、まだ見ぬ地平線の向こうに")
                        .font(.caption).foregroundStyle(.secondary)
                }.opacity(reduceMotion && detailVisible ? 0 : 1)
                    .offset(y: detailVisible && !reduceMotion ? -(height + 204) : 0)
                    .animation(reduceMotion ? .linear(duration: 0.15) :
                        .timingCurve(0.16, 0.86, 0.28, 1, duration: 0.30)
                            .delay(detailVisible ? 0.084 : 0), value: detailVisible)
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("还没有旅途", systemImage: "suitcase.rolling")
                    } description: { Text("创建一次旅行，再慢慢安排想去的地方。") }
                    actions: { Button("创建旅行") { creating = true }.buttonStyle(.borderedProminent) }
                }
                VStack(spacing: 0) {
                    let topIDs = Set(JourneyArchiveOrdering.topTrips(store.trips, today: Date.now.dayString).map(\.id))
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        let storageSlot = max(0, index - topIDs.count) + yearGroups.keys.filter { $0 < index }.count
                        if let group = yearGroups[index] {
                            JourneyArchiveYearCard(year: group.year, count: group.count)
                                .frame(height: 204)
                                .visualEffect { content, proxy in
                                    content.rotation3DEffect(.radians(ArchiveStorage.angle(midY: proxy.frame(in: .named("journey-archive")).midY, viewportHeight: height, baseMidY: proxy.frame(in: .named("journey-archive")).midY - CGFloat(storageSlot) * 88, enabled: !typeSize.isAccessibilitySize && !reduceMotion)), axis: (x: 1, y: 0, z: 0), perspective: proxy.size.width / 1000)
                                        .offset(y: ArchiveStorage.packingOffset(midY: proxy.frame(in: .named("journey-archive")).midY, viewportHeight: height, enabled: !typeSize.isAccessibilitySize && !reduceMotion))
                                }
                                .frame(height: typeSize.isAccessibilitySize ? 204 : 88, alignment: .top)
                                .background(GeometryReader { proxy in
                                    Color.clear.preference(key: ArchiveDividerFrames.self,
                                        value: [index: proxy.frame(in: .named("journey-archive"))])
                                })
                                .opacity(openedID == nil || !transitionStarted ? 1 : 0)
                                .zIndex(Double(index) - 0.5)
                        }
                        let isTop = topIDs.contains(trip.id)
                        let compact = !isTop && index != trips.count - 1 && !typeSize.isAccessibilitySize
                        let beforeStorage = isTop && index + 1 < trips.count && !topIDs.contains(trips[index + 1].id)
                        Button { open(trip, index: index, viewportHeight: height) } label: {
                            JourneyArchiveCard(trip: trip, colorIndex: index, photo: coverPhoto(trip))
                                .frame(height: 204)
                                .visualEffect { content, proxy in
                                    content.rotation3DEffect(.radians(ArchiveStorage.angle(midY: proxy.frame(in: .named("journey-archive")).midY, viewportHeight: height, baseMidY: proxy.frame(in: .named("journey-archive")).midY - CGFloat(storageSlot + (yearGroups[index] == nil ? 0 : 1)) * 88, enabled: !isTop && !typeSize.isAccessibilitySize && !reduceMotion)), axis: (x: 1, y: 0, z: 0), perspective: proxy.size.width / 1000)
                                        .offset(y: ArchiveStorage.packingOffset(midY: proxy.frame(in: .named("journey-archive")).midY, viewportHeight: height, enabled: !isTop && !typeSize.isAccessibilitySize && !reduceMotion))
                                }
                                .frame(height: compact ? 88 : 204, alignment: .top)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ArchiveCardFrames.self, value: [trip.id: proxy.frame(in: .named("journey-archive"))])
                        })
                        .opacity(openedID == nil || !transitionStarted ? 1 : 0)
                        .zIndex(Double(index))
                        .contextMenu {
                            Button("编辑旅途", systemImage: "pencil") { editing = trip }
                            DestructiveMenuButton(title: "删除旅途", systemImage: "trash") { deleting = trip }
                        }
                        .accessibilityIdentifier("archive-trip-\(trip.id)")
                        .accessibilityHint(isTop ? "置顶旅途，打开旅行详情" : "打开旅行详情")
                        .padding(.bottom, isTop && index + 1 < trips.count
                            ? 24 + (beforeStorage ? ArchiveStorage.packingReserve(viewportHeight: height,
                                enabled: !typeSize.isAccessibilitySize && !reduceMotion) : 0) : 0)
                    }
                }
                VStack(spacing: 24) {
                    Text("\(trips.count) 次旅途").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    if !independent.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("未加入行程").font(.headline)
                            ForEach(independent) { marker in
                                Button { store.selectedMarker = marker; independentDetail = marker } label: {
                                    PlaceSelectionRow(marker: marker).fullRowActionLabel()
                                }.buttonStyle(.plain).accessibilityIdentifier("independent-marker-\(marker.id)")
                            }
                        }.padding(16).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
                    }
                }.opacity(reduceMotion && detailVisible ? 0 : 1)
                    .offset(y: detailVisible && !reduceMotion ? (height + 204) : 0)
                    .animation(reduceMotion ? .linear(duration: 0.15) :
                        .timingCurve(0.16, 0.86, 0.28, 1, duration: 0.30)
                            .delay(detailVisible ? 0.084 : 0), value: detailVisible)
            }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 84).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDisabled(openedID != nil)
            .refreshable { await store.refresh(force: true) }
            .accessibilityIdentifier("archive-trip-list")
    }

    private func open(_ trip: Trip, index: Int, viewportHeight: CGFloat) {
        guard openedID == nil, let frame = cardFrames[trip.id] else { return }
        openingFrame = frame
        slotViewportHeight = viewportHeight
        let topIDs = Set(JourneyArchiveOrdering.topTrips(store.trips, today: Date.now.dayString).map(\.id))
        transferCards = trips.enumerated().compactMap { position, value in
            cardFrames[value.id].map { ArchiveTransferCard(trip: value, index: position, frame: $0,
                photo: coverPhoto(value), isTop: topIDs.contains(value.id)) }
        }
        transferDividers = dividerFrames.compactMap { position, frame in
            yearGroups[position].map { group in
                ArchiveTransferDivider(index: position, frame: frame, year: group.year, count: group.count)
            }
        }
        openingIndex = index
        closing = false
        transitionStarted = true
        cardInList = false
        destinationFrame = openingFrame
        headerGeometry.frame = .zero
        openedID = trip.id
    }
    @MainActor private func beginTransition(_ trip: Trip) async {
        guard !detailVisible else { return }
        var previous = headerGeometry.frame
        var stableFrames = 0
        while stableFrames < 2 {
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard openedID == trip.id, !closing else { return }
            let current = headerGeometry.frame
            if !current.isEmpty && current == previous { stableFrames += 1 }
            else { stableFrames = 0 }
            previous = current
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            destinationFrame = previous
        }
        detailVisible = true
    }

    private func close() {
        guard openedID != nil, !closing else { return }
        closing = true
        path = []
        destinationFrame = headerGeometry.frame
        cardInList = false
        detailVisible = false
    }
}

private struct JourneyArchiveYearCard: View {
    let year: Int
    let count: Int
    @Environment(\.colorScheme) private var colorScheme
    private var seed: UInt64 { UInt64(max(0, year)) &* 2_654_435_761 }
    private var tint: Color { Color(hue: Double(seed % 360) / 360, saturation: 0.44, brightness: colorScheme == .dark ? 0.88 : 0.40) }
    private var paper: Color { Color(hue: Double(seed % 360) / 360, saturation: colorScheme == .dark ? 0.38 : 0.22, brightness: colorScheme == .dark ? 0.30 : 0.92) }
    var body: some View {
        HStack(spacing: 16) {
            Text(String(year)).font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
            Spacer(minLength: 0)
            Text("\(count)次旅途").font(.footnote)
        }
        .foregroundStyle(tint)
        .frame(height: 38).padding(22)
        .frame(maxWidth: .infinity, minHeight: 204, maxHeight: 204, alignment: .topLeading)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(paper)
                .overlay {
                    Canvas { context, size in
                        let variant = Int(seed % 3)
                        for index in 0..<7 {
                            let x = size.width * Double((seed &+ UInt64(index * 73)) % 100) / 100
                            let y = 102 + Double((seed &+ UInt64(index * 29)) % 84)
                            let radius = 22 + Double((seed &+ UInt64(index * 11)) % 44)
                            var path = Path()
                            if variant == 0 {
                                path.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                            } else if variant == 1 {
                                path.move(to: CGPoint(x: x - radius, y: y))
                                path.addQuadCurve(to: CGPoint(x: x + radius * 2, y: y - 32), control: CGPoint(x: x, y: y - 72))
                            } else {
                                path.move(to: CGPoint(x: x - radius, y: y + radius))
                                path.addLine(to: CGPoint(x: x, y: y - radius))
                                path.addLine(to: CGPoint(x: x + radius, y: y + radius))
                            }
                            context.stroke(path, with: .color(tint.opacity(0.12)), lineWidth: 1)
                        }
                        var arc = Path()
                        arc.move(to: CGPoint(x: size.width * 0.45, y: 50))
                        arc.addQuadCurve(to: CGPoint(x: size.width + 30, y: 100),
                            control: CGPoint(x: size.width * 0.7, y: Double(seed % 40) + 16))
                        context.stroke(arc, with: .color(tint.opacity(0.13)), lineWidth: 1)
                    }.accessibilityHidden(true)
                }.clipShape(RoundedRectangle(cornerRadius: 26))
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("archive-year-\(year)")
    }
}

private struct ArchiveDividerFrames: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct ArchiveTransferDivider {
    let index: Int
    let frame: CGRect
    let year: Int
    let count: Int
}

private struct ArchiveCardFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum ArchiveStorage {
    static func packingReserve(viewportHeight: CGFloat, enabled: Bool = true) -> CGFloat {
        enabled ? max(0, min(48, viewportHeight * 0.12)) : 0
    }
    static func packingOffset(midY: CGFloat, viewportHeight: CGFloat, enabled: Bool = true) -> CGFloat {
        guard enabled, viewportHeight > 0 else { return 0 }
        let boundary = viewportHeight / 2
        let progress = max(0, min(1, midY / boundary))
        // Integrate a linear spacing gradient: tighter above, unchanged below the midpoint.
        let lift = packingReserve(viewportHeight: viewportHeight)
        return -lift * progress * (2 - progress)
    }
    static func angle(midY: CGFloat, viewportHeight: CGFloat, baseMidY: CGFloat? = nil, enabled: Bool = true) -> Double {
        guard enabled, viewportHeight > 0 else { return 0 }
        let flatBoundary = max(viewportHeight / 2, baseMidY ?? 0)
        // Reach full tilt above the bottom controls, linearly from the flat upper half.
        let tiltBoundary = max(flatBoundary + 1, viewportHeight - 84)
        let progress = max(0, min(1, (midY - flatBoundary) / (tiltBoundary - flatBoundary)))
        return -60 * Double(progress) * .pi / 180
    }
    static func transform(enabled: Bool, midY: CGFloat, viewportHeight: CGFloat, baseMidY: CGFloat? = nil) -> CATransform3D {
        guard enabled else { return CATransform3DIdentity }
        var transform = CATransform3DIdentity
        transform.m34 = -1 / 1000
        return CATransform3DConcat(
            CATransform3DRotate(transform, angle(midY: midY, viewportHeight: viewportHeight, baseMidY: baseMidY), 1, 0, 0),
            CATransform3DMakeTranslation(0, packingOffset(midY: midY, viewportHeight: viewportHeight), 0))
    }
}

private struct JourneyArchiveCard: View {
    let trip: Trip
    let colorIndex: Int
    var photo: UIImage? = nil
    var body: some View {
        let today = Date.now.dayString
        let ongoing = JourneyArchiveOrdering.isOngoing(trip, today: today)
        let status = trip.startDate > today ? "即将出发" : trip.endDate < today ? "旅行回忆" : "旅行中"
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                PlaceIconView(emoji: trip.emoji ?? "✈️", size: 26).padding(.top, 2)
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.name).font(.title3.weight(.semibold)).lineLimit(2)
                    Text("\(trip.startDate) — \(trip.endDate)").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if ongoing {
                    HStack(spacing: 5) {
                        Circle().fill(Color(red: 0.60, green: 0.73, blue: 0.63))
                            .frame(width: 6, height: 6).accessibilityHidden(true)
                        Text("旅途中").font(.caption).foregroundStyle(.secondary)
                    }
                    .fixedSize().padding(.top, 4)
                    .accessibilityIdentifier("archive-ongoing-\(trip.id)")
                }
            }
            Spacer(minLength: 8)
            HStack {
                if !ongoing { Text(status).font(.subheadline.weight(.medium)) }
                Spacer()
                Text("\(trip.days.count) 天 · \(Set(trip.days.flatMap(\.markerIds) + (trip.markerIds ?? [])).count) 个地点")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { geometry in
                let base = Color(uiColor: .systemBackground)
                ZStack {
                    base
                    LinearGradient(colors: [Theme.color(colorIndex).opacity(0.16), Theme.color(colorIndex).opacity(0.04)],
                        startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .saturation(0.64)
                        LinearGradient(stops: [.init(color: base, location: 0),
                            .init(color: base.opacity(0.96), location: 0.32),
                            .init(color: base.opacity(0.72), location: 0.58),
                            .init(color: base.opacity(0.18), location: 1)],
                            startPoint: .leading, endPoint: .trailing)
                        LinearGradient(colors: [.clear, base.opacity(0.92)], startPoint: .center, endPoint: .bottom)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 26))
            }
        }
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(Color(uiColor: .separator).opacity(0.12)) }
        .accessibilityElement(children: .combine)
    }
}

// Scrolling updates geometry without invalidating the archive and its card stack.
private final class ArchiveHeaderGeometry {
    var frame = CGRect.zero
}

private struct ArchiveHeaderFrame: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

private struct ArchiveTransferCard: Identifiable {
    let trip: Trip
    let index: Int
    let frame: CGRect
    let photo: UIImage?
    let isTop: Bool
    var id: String { trip.id }
}

// UIKit animates cached pixels; SwiftUI/List do no layout or blur work per frame.
private struct ArchiveCardTransition: UIViewRepresentable {
    let cards: [ArchiveTransferCard]
    let dividers: [ArchiveTransferDivider]
    let selectedID: String
    let destination: CGRect
    let height: CGFloat
    let expanded: Bool
    let handedOff: Bool
    let reduceMotion: Bool
    let onCompletion: () -> Void
    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var baseMidY: CGFloat? {
        (dividers.map { $0.frame.minY } + cards.filter { !$0.isTop }.map { $0.frame.minY }).min().map { $0 + 102 }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false
        // The shared SwiftUI mask owns clipping, including the bottom safe-area strip.
        for card in cards where card.trip.id == selectedID ||
            (card.frame.minY < height + 204 && card.frame.minY + 408 > 0) {
            let renderer = ImageRenderer(content: JourneyArchiveCard(trip: card.trip, colorIndex: card.index, photo: card.photo)
                .frame(width: card.frame.width, height: 204)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, typeSize))
            renderer.scale = displayScale
            guard let image = renderer.uiImage else { continue }
            let view = UIImageView(image: image)
            view.frame = CGRect(x: card.frame.minX, y: card.frame.minY, width: card.frame.width, height: 204)
            let plane = UIView(frame: CGRect(x: 0, y: 0, width: card.frame.maxX, height: height))
            plane.layer.zPosition = CGFloat(card.index)
            container.addSubview(plane)
            plane.addSubview(view)
            context.coordinator.planes[card.id] = plane
            view.layer.transform = ArchiveStorage.transform(enabled: !card.isTop && !typeSize.isAccessibilitySize && !reduceMotion, midY: card.frame.minY + 102, viewportHeight: height, baseMidY: baseMidY)
            context.coordinator.views[card.id] = view
            // The absent card retains its original slot pose throughout the round trip.
            if card.id == selectedID {
                context.coordinator.slotBounds = view.bounds
                context.coordinator.slotPosition = view.layer.position
                context.coordinator.slotTransform = view.layer.transform
            }

        }
        for divider in dividers where divider.frame.minY < height + 204 && divider.frame.minY + 408 > 0 {
            let renderer = ImageRenderer(content: JourneyArchiveYearCard(year: divider.year, count: divider.count)
                .frame(width: divider.frame.width, height: 204)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, typeSize))
            renderer.scale = displayScale
            if let image = renderer.uiImage {
                let view = UIImageView(image: image)
                view.frame = CGRect(x: divider.frame.minX, y: divider.frame.minY, width: divider.frame.width, height: 204)
                let plane = UIView(frame: CGRect(x: 0, y: 0, width: divider.frame.maxX, height: height))
                plane.layer.zPosition = CGFloat(divider.index) - 0.5
                container.addSubview(plane)
                plane.addSubview(view)
                context.coordinator.dividerPlanes[divider.index] = plane
                view.layer.transform = ArchiveStorage.transform(enabled: !typeSize.isAccessibilitySize && !reduceMotion, midY: divider.frame.minY + 102, viewportHeight: height, baseMidY: baseMidY)
                context.coordinator.dividerViews[divider.index] = view
            }
        }
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        guard let selected = coordinator.views[selectedID] else { return }
        if coordinator.expanded == expanded {
            selected.isHidden = handedOff
            return
        }
        let currentLayer = selected.layer.presentation()
        let currentBounds = currentLayer?.bounds ?? selected.bounds
        let currentPosition = currentLayer?.position ?? selected.layer.position
        let currentTransform = currentLayer?.transform ?? selected.layer.transform
        let snapshots = Array(coordinator.views.values) + Array(coordinator.dividerViews.values)
        let planes = Array(coordinator.planes.values) + Array(coordinator.dividerPlanes.values)
        let planeTransforms = planes.map { $0.layer.presentation()?.transform ?? $0.layer.transform }
        let currentAlphas = snapshots.map { CGFloat($0.layer.presentation()?.opacity ?? $0.layer.opacity) }
        coordinator.animator?.stopAnimation(true)
        for (snapshot, alpha) in zip(snapshots, currentAlphas) { snapshot.alpha = alpha }
        for (plane, transform) in zip(planes, planeTransforms) { plane.layer.transform = transform }
        if selected.isHidden {
            selected.layer.transform = CATransform3DIdentity
            selected.frame = destination
        } else {
            selected.bounds = currentBounds
            selected.layer.position = currentPosition
            selected.layer.transform = currentTransform
        }
        selected.isHidden = false
        if reduceMotion && expanded {
            selected.layer.transform = CATransform3DIdentity
            selected.frame = destination
            selected.alpha = 0
        }
        coordinator.expanded = expanded
        guard let card = cards.first(where: { $0.id == selectedID }) else { return }
        let source = CGRect(x: coordinator.slotPosition.x - coordinator.slotBounds.width / 2,
            y: coordinator.slotPosition.y - coordinator.slotBounds.height / 2,
            width: coordinator.slotBounds.width, height: coordinator.slotBounds.height)
        let sourceTransform = coordinator.slotTransform
        let upperBottom = max(cards.filter { $0.index < card.index }.map { $0.frame.maxY + 204 }.max() ?? 0,
            dividers.filter { $0.index <= card.index }.map { $0.frame.minY + 204 }.max() ?? 0)
        let lowerTop = min(cards.filter { $0.index > card.index }.map { $0.frame.minY }.min() ?? height,
            dividers.filter { $0.index > card.index }.map { $0.frame.minY }.min() ?? height)
        let animator: UIViewPropertyAnimator
        if reduceMotion {
            animator = UIViewPropertyAnimator(duration: 0.15, curve: .linear)
        } else {
            // Cubic approximation of ln(x): fast departure, long gentle settle.
            animator = UIViewPropertyAnimator(duration: 0.30,
                timingParameters: UICubicTimingParameters(controlPoint1: CGPoint(x: 0.16, y: 0.86),
                    controlPoint2: CGPoint(x: 0.28, y: 1.0)))
        }
        animator.addAnimations {
            if reduceMotion {
                selected.alpha = expanded ? 1 : 0
            } else {
                let target = expanded ? destination : source
                selected.bounds = CGRect(origin: .zero, size: target.size)
                selected.center = CGPoint(x: target.midX, y: target.midY)
                selected.layer.transform = expanded ? CATransform3DIdentity : sourceTransform
            }
        }
        let moveRack: () -> Void = {
            for other in cards where other.id != selectedID {
                if reduceMotion { coordinator.views[other.id]?.alpha = expanded ? 0 : 1 }
                coordinator.planes[other.id]?.transform = CGAffineTransform(translationX: 0,
                    y: expanded && !reduceMotion ? (other.index < card.index ? -max(0, upperBottom) - 48 : max(0, height - lowerTop) + 252) : 0)
            }
            for divider in dividers {
                if reduceMotion { coordinator.dividerViews[divider.index]?.alpha = expanded ? 0 : 1 }
                coordinator.dividerPlanes[divider.index]?.transform = CGAffineTransform(translationX: 0,
                    y: expanded && !reduceMotion ? (divider.index <= card.index ? -max(0, upperBottom) - 48 : max(0, height - lowerTop) + 252) : 0)
            }
        }
        animator.addAnimations(moveRack, delayFactor: expanded && !reduceMotion ? 0.28 : 0)
        animator.addCompletion { position in
            guard position == .end else { return }
            onCompletion()
        }
        coordinator.animator = animator
        animator.startAnimation()
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) {
        coordinator.animator?.stopAnimation(true)
    }
    final class Coordinator {
        var planes: [String: UIView] = [:]
        var dividerPlanes: [Int: UIView] = [:]
        var views: [String: UIImageView] = [:]
        var dividerViews: [Int: UIImageView] = [:]
        var slotBounds = CGRect.zero
        var slotPosition = CGPoint.zero
        var slotTransform = CATransform3DIdentity
        var expanded: Bool = false
        var animator: UIViewPropertyAnimator?
    }
}


struct JourneyArchiveYearGroup: Equatable {
    let year: Int
    let count: Int
}

enum JourneyArchiveOrdering {
    /// Receives the displayed order; top trips retain their own full-card group.
    static func yearGroups(_ trips: [Trip], today: String) -> [Int: JourneyArchiveYearGroup] {
        let topIDs = Set(topTrips(trips, today: today).map(\.id))
        let remaining = trips.enumerated().filter { !topIDs.contains($0.element.id) }
        let counts = Dictionary(grouping: remaining, by: { String($0.element.startDate.prefix(4)) })
        var groups: [Int: JourneyArchiveYearGroup] = [:]
        var previousYear: Int?
        for (index, trip) in remaining {
            guard let year = Int(trip.startDate.prefix(4)) else { continue }
            if year != previousYear { groups[index] = JourneyArchiveYearGroup(year: year, count: counts[String(year)]?.count ?? 0) }
            previousYear = year
        }
        return groups
    }
    static func isOngoing(_ trip: Trip, today: String) -> Bool {
        trip.startDate <= today && trip.endDate >= today
    }
    static func topTrips(_ trips: [Trip], today: String) -> [Trip] {
        let ongoing = trips.filter { isOngoing($0, today: today) }.sorted(by: newestFirst)
        if !ongoing.isEmpty { return ongoing }
        let top = trips.filter { $0.startDate > today }.min {
            $0.startDate == $1.startDate ? $0.id < $1.id : $0.startDate < $1.startDate
        } ?? trips.min {
            let a = abs(Date.fromDay($0.startDate).timeIntervalSince(Date.fromDay(today)))
            let b = abs(Date.fromDay($1.startDate).timeIntervalSince(Date.fromDay(today)))
            return a == b ? $0.id < $1.id : a < b
        }
        return top.map { [$0] } ?? []
    }
    static func sorted(_ trips: [Trip], today: String) -> [Trip] {
        let top = topTrips(trips, today: today)
        let topIDs = Set(top.map(\.id))
        let remainder = trips.filter { !topIDs.contains($0.id) }.sorted(by: newestFirst)
        return top + remainder
    }
    private static func newestFirst(_ a: Trip, _ b: Trip) -> Bool {
        a.startDate == b.startDate ? a.id < b.id : a.startDate > b.startDate
    }
}

private struct ArchiveDetailScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectHidden(true, for: .top)
        } else { content }
    }
}

struct JourneyDayEditor: View {
    @ObservedObject var store: AppStore
    @State var draft: DayEditorDraft
    @Environment(\.dismiss) private var dismiss
    private var trip: Trip? { store.trips.first { $0.id == draft.tripID } }
    private var places: [Marker] { trip.map { store.tripPlaces($0) } ?? [] }
    private var dayNumber: Int {
        guard let trip else { return 1 }
        return draft.day.flatMap { day in trip.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id }.map { $0 + 1 } } ?? (trip.days.count + 1)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", dayNumber)).font(.largeTitle).monospacedDigit()
                        Rectangle().fill(.tertiary).frame(width: 20, height: 0.5)
                        Text(draft.date).font(.subheadline).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                    VStack(alignment: .leading, spacing: 12) {
                        JourneyEditorHeading(title: "当日主题")
                        TextField("给这一天起个名字（可留空）", text: $draft.title, axis: .vertical)
                            .font(.title3).lineLimit(1...3).accessibilityIdentifier("day-editor-title")
                        Divider()
                    }
                    VStack(alignment: .leading, spacing: 14) {
                        JourneyEditorHeading(title: "旅途中的地点")
                        Text(places.isEmpty ? "本次旅途还没有地点，可先添加这一天。" : "从本次旅途已有地点中选择，也可以暂不选择。")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(places) { marker in
                            Button {
                                if draft.markerIDs.contains(marker.id) { draft.markerIDs.removeAll { $0 == marker.id } }
                                else { draft.markerIDs.append(marker.id) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: draft.markerIDs.contains(marker.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(draft.markerIDs.contains(marker.id) ? Color.primary : Color.secondary)
                                    Text(marker.title).foregroundStyle(.primary)
                                    Spacer(minLength: 0)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityValue(draft.markerIDs.contains(marker.id) ? "已选" : "未选")
                                .accessibilityIdentifier("day-editor-place-\(marker.id)")
                            Divider()
                        }
                    }
                }.padding(24).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(uiColor: .systemBackground))
            .navigationTitle(draft.day == nil ? "添加一天" : "编辑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }.accessibilityLabel("取消")
                }
            }
            .safeAreaInset(edge: .bottom) {
                JourneyEditorSubmit(title: draft.day == nil ? "添加一天" : "保存当天", enabled: !store.saving,
                    identifier: "day-editor-submit", background: Color(uiColor: .systemBackground)) {
                    if store.submitDayEditor(draft) { dismiss() }
                }
            }
        }
        .journeyError(store: store)
        .presentationDetents([.large])
    }
}
