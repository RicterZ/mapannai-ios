import SwiftUI
import UniformTypeIdentifiers
import UIKit
import CoreImage

struct JourneyDaysContents: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    var archiveColorIndex: Int? = nil
    var archiveHeaderVisible = true
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
        List {
            if let archiveColorIndex {
                Section {
                    JourneyArchiveCard(trip: trip, colorIndex: archiveColorIndex)
                        .frame(height: 204)
                        .opacity(archiveHeaderVisible ? 1 : 0)
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

            ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, day in
                Section {
                NavigationLink(value: JourneyDestination.day(trip.id, day.id)) {
                    dayRow(day, index: index)
                        .contentShape(Rectangle())
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: NativeDayFrames.self, value: [day.id: geometry.frame(in: .global)])
                        })
                }.buttonStyle(.automatic).accessibilityIdentifier("journey-day-\(day.id)")
                    .listRowBackground(Color(uiColor: .systemBackground)
                        .overlay(Color(uiColor: .tertiarySystemFill).opacity(targetedDayID == day.id ? 1 : 0)))
                    .animation(reduceMotion ? nil : .default, value: targetedDayID == day.id)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button { deletion = day } label: { Image(systemName: "trash") }
                            .accessibilityLabel("删除")
                            .buttonStyle(.automatic).tint(.red).disabled(trip.days.count <= 1 || store.saving)
                    }
                    .contextMenu {
                        DestructiveMenuButton(title: "删除日期", systemImage: "trash") { deletion = day }
                            .disabled(trip.days.count <= 1 || store.saving)
                    }
                }
            }
            if !unscheduledPlaces.isEmpty || !store.demo {
                Section {
                    ForEach(unscheduledPlaces) { marker in
                        PlaceSelectionRow(marker: marker)
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
                    Button { store.beginAddingPlace(tripID: trip.id) } label: {
                        Label("添加地点", systemImage: "plus").fullRowActionLabel()
                    }.foregroundStyle(Theme.accent)
                } header: {
                    Text("未安排日期")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
                  footer: { Text("已收藏到这次旅行，之后可以安排到某一天。") }
            }
            Section {
                Button { Task {
                    let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: .fromDay(trip.endDate))!.dayString
                    _ = await store.perform { client in
                        try await client.mutate("trips/\(APIClient.id(trip.id))/days", method: "POST", body: ["date": next])
                        try await client.mutate("trips/\(APIClient.id(trip.id))", method: "PUT", body: ["endDate": next])
                    }
                }} label: { Label("添加一天", systemImage: "plus").fullRowActionLabel() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(store.saving)
                    .accessibilityIdentifier("journey-add-day")
                Button { editing = true } label: {
                    Label("编辑旅行", systemImage: "pencil").fullRowActionLabel()
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .disabled(store.saving).accessibilityIdentifier("journey-edit-trip")
            } header: {
                Color.clear.frame(height: 16).accessibilityHidden(true)
            }
            }
        }
            .onPreferenceChange(ArchiveHeaderFrame.self) { if !$0.isEmpty { onArchiveHeaderFrame($0) } }
            .listSectionSpacing(12)
            .onPreferenceChange(NativeDayFrames.self) { nativeDayFrames = $0 }
            .sensoryFeedback(.selection, trigger: targetedDayID) { _, newValue in newValue != nil }
            .background(NativePlaceListDrop(frames: nativeDayFrames, prefix: "trip-place/" + trip.id + "/", onTarget: { targetedDayID = $0 }) { id, dayID in
                if let day = trip.days.first(where: { $0.id == dayID }) {
                    _ = assignPreviewPlaces(["trip-place/" + trip.id + "/" + id], to: day)
                }
            })
            .sheet(isPresented: $editing) { TripEditorView(store: store, trip: trip).presentationDragIndicator(.visible) }
            .sheet(item: $deletion) { day in
                DayDeletionView(store: store, day: day)
            }
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

    private func dayRow(_ day: TripDay, index: Int) -> some View {
        let title = day.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let titles = day.markerIds.compactMap { id in store.markers.first { $0.id == id }?.title }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("第\(index + 1)天").font(.title3.weight(.bold))
                Spacer(minLength: 12)
                Text(Date.fromDay(day.date), format: .dateTime.month().day().weekday(.abbreviated))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !title.isEmpty && title != "第\(index + 1)天" && title != day.date {
                Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            if !titles.isEmpty {
                Text(titles.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.color(day.colorIndex ?? 0)).frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(day.markerIds.isEmpty ? "尚未安排地点" : "\(day.markerIds.count) 个地点")
                if !day.chains.isEmpty {
                    Text("· \(day.chains.count) 条路线")
                }
            }.font(.footnote).foregroundStyle(.secondary)
        }.foregroundStyle(.primary).padding(.vertical, 10).contentShape(Rectangle())
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
    @State private var detailVisible = false
    @State private var cardInList = false
    @State private var closing = false
    @State private var transitionStarted = false
    @State private var destinationFrame = CGRect.zero
    @State private var headerGeometry = ArchiveHeaderGeometry()
    @State private var cardFrames: [String: CGRect] = [:]
    @State private var transferCards: [ArchiveTransferCard] = []
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
        let today = Date.now.dayString
        return store.trips.sorted {
            let a = archiveOrder($0, today: today), b = archiveOrder($1, today: today)
            if a != b { return a < b }
            return $0.id < $1.id
        }
    }
    private func archiveOrder(_ trip: Trip, today: String) -> String {
        if trip.startDate <= today && trip.endDate >= today { return "0/" + trip.startDate }
        if trip.startDate > today { return "1/" + trip.startDate }
        return "2/" + trip.endDate.map { $0.wholeNumberValue.map { String(9 - $0) } ?? String($0) }.joined()
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                archive(height: geometry.size.height)
                    .allowsHitTesting(openedID == nil)
                    .accessibilityHidden(openedID != nil)
                if let trip = openedTrip {
                    ZStack(alignment: .topLeading) {
                        JourneyDaysContents(store: store, trip: trip, archiveColorIndex: openingIndex,
                            archiveHeaderVisible: cardInList,
                            onArchiveHeaderFrame: {
                                let origin = geometry.frame(in: .global).origin
                                headerGeometry.frame = $0.offsetBy(dx: -origin.x, dy: -origin.y)
                            })
                            .id(trip.id)
                            .listStyle(.insetGrouped)
                            .contentMargins(.top, 16, for: .scrollContent)
                            .scrollContentBackground(.hidden)
                            .frame(maxWidth: 640).frame(maxWidth: .infinity)
                            .opacity(detailVisible ? 1 : 0)
                            .animation(.easeOut(duration: reduceMotion ? 0.15 : 0.22)
                                .delay(detailVisible && !reduceMotion ? 0.12 : 0), value: detailVisible)
                            .allowsHitTesting(cardInList)
                            .zIndex(Double(openingIndex))
                            .task(id: trip.id) { await beginTransition(trip) }
                        if transitionStarted {
                            ArchiveCardTransition(cards: transferCards, selectedID: trip.id,
                                destination: destinationFrame, height: geometry.size.height,
                                expanded: detailVisible, handedOff: cardInList, reduceMotion: reduceMotion) {
                                    if detailVisible && !closing {
                                        cardInList = true
                                        store.select(trip: trip, focus: false)
                                    } else if closing {
                                        openedID = nil
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
            .clipped()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(openedID == nil ? "我的旅途" : "")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Color(uiColor: .label))
        .toolbar {
            if let trip = openedTrip {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) { Image(systemName: "xmark").foregroundStyle(Color(uiColor: .label)) }
                        .accessibilityLabel("返回我的旅途").accessibilityIdentifier("archive-detail-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { onSelect(trip, nil) } label: { Label("地图", systemImage: "map").foregroundStyle(Color(uiColor: .label)) }
                        .accessibilityIdentifier("archive-detail-map")
                }
            } else {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { HStack(spacing: 6) { Image(systemName: "plus"); Text("新建") }.foregroundStyle(Color(uiColor: .label)) }
                        .accessibilityLabel("创建旅行").accessibilityIdentifier("archive-create")
                }
            }
        }
        .navigationDestination(for: JourneyDestination.self) { destination in
            if case let .day(tripID, dayID) = destination,
               let trip = store.trips.first(where: { $0.id == tripID }),
               let day = trip.days.first(where: { $0.id == dayID }) {
                DayContentsView(store: store, day: day, onViewRoute: { onSelect(trip, day) })
                    .listStyle(.insetGrouped)
                    .navigationTitle("第\((trip.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id } ?? 0) + 1)天")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { onSelect(trip, day) } label: { Label("地图", systemImage: "map").foregroundStyle(Color(uiColor: .label)) }
                                .accessibilityIdentifier("archive-day-map")
                        }
                    }
                    .onAppear { store.select(trip: trip, day: day, focus: false) }
            }
        }
        .onPreferenceChange(ArchiveCardFrames.self) { if openedID == nil { cardFrames = $0 } }
        .onAppear { if let trip = openedTrip { store.select(trip: trip, focus: false) } }
        .onChange(of: path) { _, value in
            if value.isEmpty, let trip = openedTrip { store.select(trip: trip, focus: false) }
        }
        .onChange(of: store.placeSearchPresented) { _, presented in
            if presented, !mapVisible, let trip = openedTrip { onSelect(trip, store.day) }
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
        .sheet(isPresented: $creating) { TripEditorView(store: store, trip: nil).presentationDetents([.medium]) }
        .sheet(item: $editing) { TripEditorView(store: store, trip: $0) }
        .sheet(item: $deleting) { TripDeletionView(store: store, trip: $0) }
        .sheet(item: Binding(get: { mapVisible ? nil : store.tripSaveRecovery }, set: { if !mapVisible { store.tripSaveRecovery = $0 } })) { draft in
            TripEditorView(store: store, trip: draft.trip, initial: draft)
        }
        .alert("操作失败", isPresented: Binding(get: { !mapVisible && store.errorMessage != nil }, set: { if !$0 && !mapVisible { store.errorMessage = nil } })) {
            if store.canResumeFailedSave { Button("继续编辑") { store.resumeFailedSave() } }
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private func archive(height: CGFloat) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("旅の目的地は、まだ見ぬ地平線の向こうに")
                    .font(.caption).foregroundStyle(.secondary)
                    .opacity(detailVisible ? 0 : 1)
                if trips.isEmpty {
                    ContentUnavailableView {
                        Label("还没有旅途", systemImage: "suitcase.rolling")
                    } description: { Text("创建一次旅行，再慢慢安排想去的地方。") }
                    actions: { Button("创建旅行") { creating = true }.buttonStyle(.borderedProminent) }
                }
                VStack(spacing: 0) {
                    ForEach(Array(trips.enumerated()), id: \.element.id) { index, trip in
                        let compact = index != trips.count - 1 && !typeSize.isAccessibilitySize
                        Button { open(trip, index: index) } label: {
                            JourneyArchiveCard(trip: trip, colorIndex: index)
                                .frame(height: 204)
                                .frame(height: compact ? 82 : 204, alignment: .top)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: ArchiveCardFrames.self, value: [trip.id: proxy.frame(in: .named("journey-archive"))])
                        })
                        .opacity(openedID == nil || !transitionStarted ? 1 : 0)
                        .zIndex(Double(index))
                        .contextMenu {
                            Button("编辑旅行", systemImage: "pencil") { editing = trip }
                            DestructiveMenuButton(title: "删除旅行", systemImage: "trash") { deleting = trip }
                        }
                        .accessibilityIdentifier("archive-trip-\(trip.id)")
                        .accessibilityHint("打开旅行详情")
                    }
                }
                VStack(spacing: 24) {
                    Text("\(trips.count) 次旅途").font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                    Form {
                        Section {
                            Button(action: onOpenSettings) {
                                HStack { Text("设置"); Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
                            }.foregroundStyle(Color(uiColor: .label)).accessibilityIdentifier("archive-settings")
                        }
                    }.scrollDisabled(true).scrollContentBackground(.hidden)
                        .contentMargins(.top, 0).frame(height: 70).padding(.horizontal, -20)
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
                }.opacity(detailVisible ? 0 : 1)
            }.padding(.horizontal, 16).padding(.vertical, 20).frame(maxWidth: 640).frame(maxWidth: .infinity)
        }.scrollDisabled(openedID != nil)
    }

    private func open(_ trip: Trip, index: Int) {
        guard openedID == nil, let frame = cardFrames[trip.id] else { return }
        openingFrame = frame
        transferCards = trips.enumerated().compactMap { position, value in
            cardFrames[value.id].map { ArchiveTransferCard(trip: value, index: position, frame: $0) }
        }
        openingIndex = index
        closing = false
        transitionStarted = false
        cardInList = false
        destinationFrame = openingFrame
        headerGeometry.frame = .zero
        openedID = trip.id
    }
    @MainActor private func beginTransition(_ trip: Trip) async {
        guard !transitionStarted else { return }
        var previous = CGRect.zero
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
            transitionStarted = true
        }
        do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
        guard openedID == trip.id, !closing else { return }
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

private struct ArchiveCardFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct JourneyArchiveCard: View {
    let trip: Trip
    let colorIndex: Int
    var body: some View {
        let today = Date.now.dayString
        let status = trip.startDate > today ? "即将出发" : trip.endDate < today ? "旅行回忆" : "旅行中"
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text(trip.emoji ?? "✈️").font(.system(size: 30))
                VStack(alignment: .leading, spacing: 5) {
                    Text(trip.name).font(.title3.weight(.semibold)).lineLimit(2)
                    Text("\(trip.startDate) — \(trip.endDate)").font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack {
                Text(status).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(trip.days.count) 天 · \(Set(trip.days.flatMap(\.markerIds) + (trip.markerIds ?? [])).count) 个地点")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 26).fill(Color(uiColor: .systemBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 26).fill(
                        LinearGradient(colors: [Theme.color(colorIndex).opacity(0.20), Theme.color(colorIndex).opacity(0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(Color(uiColor: .separator).opacity(0.18)) }
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
    var id: String { trip.id }
}

// UIKit animates cached pixels; SwiftUI/List do no layout or blur work per frame.
private struct ArchiveCardTransition: UIViewRepresentable {
    let cards: [ArchiveTransferCard]
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

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.isUserInteractionEnabled = false
        let ciContext = CIContext()
        for card in cards where card.trip.id == selectedID ||
            (card.frame.minY < height && card.frame.minY + 204 > 0) {
            let renderer = ImageRenderer(content: JourneyArchiveCard(trip: card.trip, colorIndex: card.index)
                .frame(width: card.frame.width, height: 204)
                .environment(\.colorScheme, colorScheme)
                .environment(\.dynamicTypeSize, typeSize))
            renderer.scale = displayScale
            guard let image = renderer.uiImage else { continue }
            let view = UIImageView(image: image)
            view.frame = CGRect(x: card.frame.minX, y: card.frame.minY, width: card.frame.width, height: 204)
            container.addSubview(view)
            context.coordinator.views[card.id] = view
            if card.id != selectedID, let cg = image.cgImage {
                let input = CIImage(cgImage: cg)
                let blurred = input.clampedToExtent().applyingFilter("CIGaussianBlur",
                    parameters: [kCIInputRadiusKey: 8 * displayScale]).cropped(to: input.extent)
                if let output = ciContext.createCGImage(blurred, from: input.extent) {
                    let overlay = UIImageView(image: UIImage(cgImage: output, scale: displayScale, orientation: .up))
                    overlay.frame = view.bounds
                    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    overlay.alpha = 0
                    view.addSubview(overlay)
                    context.coordinator.blurs[card.id] = overlay
                }
            }
        }
        return container
    }
    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        guard let selected = coordinator.views[selectedID],
              let index = cards.first(where: { $0.id == selectedID })?.index else { return }
        if coordinator.expanded == expanded {
            selected.isHidden = handedOff
            return
        }
        let currentFrame = selected.isHidden ? destination : (selected.layer.presentation()?.frame ?? selected.frame)
        coordinator.animator?.stopAnimation(true)
        selected.frame = currentFrame
        selected.isHidden = false
        if reduceMotion && expanded {
            selected.frame = destination
            selected.alpha = 0
        }
        coordinator.expanded = expanded
        let upperBottom = cards.filter { $0.index < index }.map { $0.frame.minY + 204 }.max() ?? 0
        let lowerTop = cards.filter { $0.index > index }.map { $0.frame.minY }.min() ?? height
        let animator = UIViewPropertyAnimator(duration: reduceMotion ? 0.15 : 0.48,
            timingParameters: UISpringTimingParameters(dampingRatio: 1))
        animator.addAnimations {
            for card in cards {
                guard let cardView = coordinator.views[card.id] else { continue }
                if card.id == selectedID {
                    if !reduceMotion {
                        cardView.frame = expanded ? destination : CGRect(x: card.frame.minX,
                            y: card.frame.minY, width: card.frame.width, height: 204)
                    }
                    cardView.alpha = reduceMotion && !expanded ? 0 : 1
                } else {
                    let offset = card.index < index ? -max(0, upperBottom) - 24 : max(0, height - lowerTop) + 24
                    cardView.transform = CGAffineTransform(translationX: 0,
                        y: expanded && !reduceMotion ? offset : 0)
                    cardView.alpha = expanded ? 0 : 1
                    coordinator.blurs[card.id]?.alpha = expanded && !reduceMotion ? 1 : 0
                }
            }
        }
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
        var views: [String: UIImageView] = [:]
        var blurs: [String: UIImageView] = [:]
        var expanded: Bool = false
        var animator: UIViewPropertyAnimator?
    }
}
