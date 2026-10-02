import SwiftUI

struct JourneyOverviewContents<SettingsContent: View>: View {
    @ObservedObject var store: AppStore
    @ViewBuilder var settingsContent: () -> SettingsContent
    @State private var creatingTrip = false
    @State private var editing: Trip?
    @State private var markerDeletion: Marker?
    @State private var deletion: Trip?
    private var years: [String] { Array(Set(store.trips.map { String($0.startDate.prefix(4)) })).sorted(by: >) }
    private var independent: [Marker] {
        let assigned = Set(store.trips.flatMap { ($0.markerIds ?? []) + $0.days.flatMap(\.markerIds) })
        return store.markers.filter { !assigned.contains($0.id) }
    }
    var body: some View {
        List {
            Group {
            Section {
                Button { creatingTrip = true } label: {
                    Label("添加旅途", systemImage: "plus").fullRowActionLabel()
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("create-journey")
            }

            ForEach(years, id: \.self) { year in
                Section {
                ForEach(store.trips.filter { $0.startDate.hasPrefix(year) }.sorted { $0.startDate > $1.startDate }) { trip in
                    NavigationLink(value: JourneyDestination.trip(trip.id)) { tripRow(trip) }.accessibilityIdentifier("journey-\(trip.id)")
                        .contextMenu {
                            Button("编辑旅行", systemImage: "pencil") { editing = trip }
                            DestructiveMenuButton(title: "删除旅行", systemImage: "trash") { deletion = trip }
                        }

                }
                } header: {
                    HStack(spacing: 10) {
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                        Text(year).font(.caption).foregroundStyle(.secondary).fixedSize()
                        Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5)
                    }.textCase(nil).accessibilityElement(children: .combine).accessibilityIdentifier("journey-year-\(year)")
                }
            }
            if store.trips.isEmpty { Text("暂无旅行").font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 16) }
            if !independent.isEmpty {
                Section("未加入行程") {
                    ForEach(independent) { marker in
                        Button { store.focus(marker) } label: {
                            PlaceSelectionRow(marker: marker).fullRowActionLabel()
                        }.buttonStyle(.plain)
                            .accessibilityIdentifier("independent-marker-\(marker.id)")
                            .contextMenu {
                                DestructiveMenuButton(title: "删除地点", systemImage: "trash") { markerDeletion = marker }
                            }
                    }
                }
            }
            Section {
                settingsContent()
            } header: {
                Color.clear.frame(height: 16).accessibilityHidden(true)
            }

            }.listRowBackground(Color(uiColor: .systemBackground))
        }
            .alert("删除地点？", isPresented: Binding(get: { markerDeletion != nil }, set: { if !$0 { markerDeletion = nil } })) {
                Button("取消", role: .cancel) { markerDeletion = nil }
                Button("删除", role: .destructive) {
                    if let marker = markerDeletion { store.deleteMarker(marker) }
                    markerDeletion = nil
                }
            } message: { Text("会从所有每日行程和路线中移除这个地点。") }
            .sheet(isPresented: $creatingTrip) { TripEditorView(store: store, trip: nil)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden) }
            .sheet(item: $editing) { TripEditorView(store: store, trip: $0).presentationDragIndicator(.visible) }
            .sheet(item: $deletion) { trip in
                TripDeletionView(store: store, trip: trip)
            }
    }
    private func tripRow(_ trip: Trip) -> some View {
        HStack(spacing: 12) {
            Text(trip.emoji ?? "✈️").font(.title2).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(trip.name).font(.body).foregroundStyle(.primary).lineLimit(2)
                Text("\(trip.startDate) – \(trip.endDate)").font(.footnote).foregroundStyle(.secondary)
                Text("\(trip.days.count)天 · \(Set(trip.days.flatMap(\.markerIds) + (trip.markerIds ?? [])).count)个地点")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2).contentShape(Rectangle())
    }

}

struct JourneyDaysContents: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    private var unscheduledPlaces: [Marker] {
        if store.tripPlacesPreview { return store.previewTripPlaces[trip.id] ?? [] }
        let ids = Set(trip.markerIds ?? [])
        return store.markers.filter { ids.contains($0.id) }
    }
    @State private var draggingMarker: Marker?
    @State private var dragLocation: CGPoint = .zero
    @State private var dayDropFrames: [String: CGRect] = [:]
    @State private var dropTargetDayID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var editing = false
    @State private var deletion: TripDay?
    var body: some View {
        List {
            Group {

            ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, day in
                NavigationLink(value: JourneyDestination.day(trip.id, day.id)) {
                    dayRow(day, index: index)
                        .contentShape(Rectangle())
                        .background(GeometryReader { geometry in
                            Color.clear.preference(key: TripDayDropFrames.self,
                                value: [day.id: geometry.frame(in: .global)])
                        })
                }.buttonStyle(.automatic).accessibilityIdentifier("journey-day-\(day.id)")
                    .listRowBackground(dropTargetDayID == day.id ? Color(uiColor: .tertiarySystemFill) : Color(uiColor: .systemBackground))
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
            if !unscheduledPlaces.isEmpty || !store.demo {
                Section {
                    ForEach(unscheduledPlaces) { marker in
                        PlaceSelectionRow(marker: marker)
                            .contentShape(Rectangle())
                            .onTapGesture { store.focus(marker) }
                            .accessibilityElement(children: .combine)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("trip-unscheduled-\(marker.id)")
                            .opacity(draggingMarker?.id == marker.id ? 0.3 : 1)
                            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 20) {
                                draggingMarker = marker
                            }
                            .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
                                .onChanged { drag in
                                    dragLocation = drag.location
                                    guard draggingMarker?.id == marker.id else { return }
                                    dropTargetDayID = dayDropFrames.first(where: { $0.value.contains(drag.location) })?.key
                                }
                                .onEnded { drag in
                                    guard draggingMarker?.id == marker.id else { return }
                                    if let id = dayDropFrames.first(where: { $0.value.contains(drag.location) })?.key,
                                       let day = trip.days.first(where: { $0.id == id }) {
                                        _ = assignPreviewPlaces(["trip-place/" + trip.id + "/" + marker.id], to: day)
                                    }
                                    draggingMarker = nil; dropTargetDayID = nil
                                })
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
            }.listRowBackground(Color(uiColor: .systemBackground))
        }
            .onPreferenceChange(TripDayDropFrames.self) { dayDropFrames = $0 }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                if let draggingMarker {
                    PlaceSelectionRow(marker: draggingMarker)
                        .padding(12).frame(width: 240)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 8, y: 3)
                        .position(x: dragLocation.x - geometry.frame(in: .global).minX,
                                  y: dragLocation.y - geometry.frame(in: .global).minY)
                        .allowsHitTesting(false)
                }
                }.allowsHitTesting(false)
            }
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
            dropTargetDayID = nil
        }
        store.rebuildRoutes(preservingPlannedGeometry: true)
        return true
    }

    private func dayRow(_ day: TripDay, index: Int) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.color(day.colorIndex ?? 0)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("第\(index + 1)天").font(.body).foregroundStyle(.primary)
                    Spacer(minLength: 8)
                    Text(day.date).font(.subheadline).foregroundStyle(.secondary)
                }
                let titles = day.markerIds.compactMap { id in store.markers.first { $0.id == id }?.title }.joined(separator: " · ")
                Text("\(day.markerIds.count)个地点" + (titles.isEmpty ? "" : " · " + titles))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }.padding(.vertical, 2).contentShape(Rectangle())
    }

}

private struct TripDayDropFrames: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
