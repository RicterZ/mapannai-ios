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
        let assigned = Set(store.trips.flatMap { $0.days.flatMap(\.markerIds) })
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
                Text("\(trip.days.count)天 · \(Set(trip.days.flatMap(\.markerIds)).count)个地点")
                    .font(.footnote).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 2).contentShape(Rectangle())
    }

}

struct JourneyDaysContents: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    @State private var editing = false
    @State private var deletion: TripDay?
    var body: some View {
        List {
            Group {

            ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, day in
                NavigationLink(value: JourneyDestination.day(trip.id, day.id)) { dayRow(day, index: index) }.buttonStyle(.automatic).accessibilityIdentifier("journey-day-\(day.id)")
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
            if store.tripPlacesPreview {
                Section {
                    ForEach(store.previewTripPlaces[trip.id] ?? []) { marker in
                        Button { store.focus(marker) } label: { PlaceSelectionRow(marker: marker) }
                            .buttonStyle(.plain)
                    }
                    Button { store.beginAddingPlace() } label: {
                        Label("添加地点", systemImage: "plus").fullRowActionLabel()
                    }.foregroundStyle(Theme.accent)
                } header: { Text("未安排日期") }
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
            .sheet(isPresented: $editing) { TripEditorView(store: store, trip: trip).presentationDragIndicator(.visible) }
            .sheet(item: $deletion) { day in
                DayDeletionView(store: store, day: day)
            }
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
