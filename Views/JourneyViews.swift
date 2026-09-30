import SwiftUI

struct JourneyOverviewContents<SearchContent: View, SettingsContent: View>: View {
    @ObservedObject var store: AppStore
    @ViewBuilder var searchContent: () -> SearchContent
    @ViewBuilder var settingsContent: () -> SettingsContent
    @State private var editing: Trip?
    @State private var deletion: Trip?
    private var years: [String] { Array(Set(store.trips.map { String($0.startDate.prefix(4)) })).sorted(by: >) }
    private var independent: [Marker] {
        let assigned = Set(store.trips.flatMap { $0.days.flatMap(\.markerIds) })
        return store.markers.filter { !assigned.contains($0.id) }
    }
    var body: some View {
        List {
            Section { searchContent() }
            ForEach(years, id: \.self) { year in
                Section(year) {
                ForEach(store.trips.filter { $0.startDate.hasPrefix(year) }.sorted { $0.startDate > $1.startDate }) { trip in
                    HStack(spacing: 8) {
                        Button { store.select(trip: trip) } label: {
                            HStack(spacing: 12) {
                                Text(trip.emoji ?? "✈️").font(.title3).frame(width: 40, height: 40)

                                VStack(alignment: .leading, spacing: 5) {
                                    Text(trip.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(2)
                                    Text("\(trip.startDate) – \(trip.endDate)").font(.caption).foregroundStyle(Theme.muted)
                                    Text("\(trip.days.count)天 · \(Set(trip.days.flatMap(\.markerIds)).count)个地点")
                                        .font(.caption).foregroundStyle(Theme.muted)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                            }.padding(.vertical, 4).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityIdentifier("journey-\(trip.id)")
                        .contextMenu {
                            Button("编辑旅行", systemImage: "pencil") { editing = trip }
                            Button("删除旅行", systemImage: "trash", role: .destructive) { deletion = trip }
                        }

                    }
                }
                }
            }
            if store.trips.isEmpty { Text("暂无旅行").font(.subheadline).foregroundStyle(Theme.muted).padding(.vertical, 16) }
            if !independent.isEmpty {
                Text("独立地点").font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
                ForEach(MarkerIcon.allCases) { icon in
                    let places = independent.filter { $0.icon == icon }
                    if !places.isEmpty {
                        Text("\(icon.emoji) \(icon.label) · \(places.count)").font(.caption).foregroundStyle(Theme.muted)
                        ForEach(places) { marker in
                            Button { store.focus(marker) } label: { PlaceSelectionRow(marker: marker) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Section { settingsContent() }
        }
            .sheet(item: $editing) { TripEditorView(store: store, trip: $0).presentationDragIndicator(.visible) }
            .alert("删除旅行？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    guard let trip = deletion else { return }
                    Task { _ = await store.perform { try await $0.mutate("trips/\(APIClient.id(trip.id))", method: "DELETE") }; deletion = nil }
                }
            } message: { Text("删除旅行及每日安排，保留地图地点。") }
    }
}

struct JourneyDaysContents<SearchContent: View>: View {
    @ObservedObject var store: AppStore
    @ViewBuilder var searchContent: () -> SearchContent
    let trip: Trip
    @State private var editing = false
    @State private var deletion: TripDay?
    var body: some View {
        List {
            Section { searchContent() }
            ForEach(Array(trip.days.sorted { $0.date < $1.date }.enumerated()), id: \.element.id) { index, day in
                HStack(spacing: 0) {
                    Button { store.select(trip: trip, day: day) } label: {
                        HStack(spacing: 12) {
                            Circle().fill(Theme.color(day.colorIndex ?? 0)).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("第\(index + 1)天").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                                Text(day.date).font(.caption).foregroundStyle(Theme.muted)
                                Text(day.markerIds.compactMap { id in store.markers.first { $0.id == id }?.title }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(day.markerIds.count)").font(.caption).foregroundStyle(Theme.muted)
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.muted)
                        }.padding(.vertical, 4).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("journey-day-\(day.id)")
                    .contextMenu {
                        Button("删除日期", systemImage: "trash", role: .destructive) { deletion = day }
                            .disabled(trip.days.count <= 1 || store.saving)
                    }

                }
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
            .sheet(isPresented: $editing) { TripEditorView(store: store, trip: trip).presentationDragIndicator(.visible) }
            .alert("删除当天？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) {
                    guard let day = deletion else { return }
                    Task { _ = await store.perform { try await $0.mutate(AppStore.dayPath(day), method: "DELETE") }; deletion = nil }
                }
            } message: { Text("删除当天安排，保留地图地点。") }
    }
}
