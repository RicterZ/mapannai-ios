import SwiftUI

struct TripLibraryView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var editing: Trip?
    @State private var deletion: Trip?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { store.select(trip: nil); dismiss() } label: { Label("所有地点 · \(store.markers.count)", systemImage: "mappin.and.ellipse") }
                }
                Section("我的旅行") {
                    ForEach(store.trips) { trip in
                        HStack(spacing: 12) {
                            Text(trip.emoji ?? "✈️").font(.title).frame(width: 42)
                            Button {
                                store.select(trip: trip); dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(trip.name).font(.headline).foregroundStyle(Theme.ink)
                                    Text("\(trip.startDate) — \(trip.endDate) · \(trip.days.count)天").font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)

                        }.padding(.vertical, 6)
                    }
                    if store.trips.isEmpty { Text("创建旅行，然后为每一天安排地点与路线。").foregroundStyle(.secondary) }
                    Button { creating = true } label: { Label("创建旅行", systemImage: "plus") }
                }

            }.navigationTitle("旅行")
                .toolbar { PanelCloseToolbarItem(identifier: "close-trip-library", placement: .confirmationAction) { dismiss() } }
                .refreshable { await store.refresh() }
                .sheet(isPresented: $creating) { TripEditorView(store: store, trip: nil) }
                .sheet(item: $editing) { TripEditorView(store: store, trip: $0) }
                .alert("删除旅行？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                    Button("取消", role: .cancel) { deletion = nil }
                    Button("删除", role: .destructive) {
                        guard let trip = deletion else { return }
                        Task { _ = await store.perform { try await $0.mutate("trips/\(APIClient.id(trip.id))", method: "DELETE") }; deletion = nil }
                    }
                } message: { Text("将删除旅行及其每日安排，地点仍保留在地图上。") }
        }
    }
}
struct TripEditorView: View {
    @ObservedObject var store: AppStore
    let trip: Trip?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var emoji = "✈️"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("旅行信息") {
                    TextField("旅行名称", text: $name)
                    TextField("简介", text: $description, axis: .vertical)
                    TextField("旅行图标", text: $emoji)
                }
                Section("日期") {
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                    if trip == nil { DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date) }
                    else { Text("修改开始日期会保留天数并顺移每日安排。增减天数在每日行程中操作。").font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.navigationTitle(trip == nil ? "创建旅行" : "编辑旅行").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task {
                            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请输入旅行名称"; return }
                            guard trip != nil || start.dayString <= end.dayString else { error = "结束日期不能早于开始日期"; return }
                            // Bound creation to protect against accidental multi-year ranges.
                            if trip == nil && end.timeIntervalSince(start) > 366*86400 { error = "一次最多创建 367 天，请缩短日期范围"; return }
                            let ok = await store.perform { client in
                                var body: [String: Any] = ["name": name, "description": description, "startDate": start.dayString, "emoji": emoji]
                                if let trip { try await client.mutate("trips/\(APIClient.id(trip.id))", method: "PUT", body: body) }
                                else {
                                    body["endDate"] = end.dayString
                                    let created: Trip = try await client.request("trips", method: "POST", body: body)
                                    if emoji != "✈️" { try await client.mutate("trips/\(APIClient.id(created.id))", method: "PUT", body: ["emoji": emoji]) }
                                }
                            }
                            if ok { dismiss() } else { error = store.errorMessage }
                        }}.disabled(store.saving || name.isEmpty)
                    }
                }
        }.onAppear {
            if let trip { name = trip.name; description = trip.description ?? ""; start = .fromDay(trip.startDate); end = .fromDay(trip.endDate); emoji = trip.emoji ?? "✈️" }
        }.interactiveDismissDisabled(store.saving)
    }
}
struct DayContentsView: View {
    @ObservedObject var store: AppStore
    let day: TripDay
    @Environment(\.colorScheme) private var colorScheme
    @State private var chainEditor: ChainEditRequest?
    @State private var addingMarkers = false
    @State private var editingTitle = false
    @State private var title = ""
    @State private var deletingDay = false
    @State private var deletingChain: Int?
    @State private var collapsedRoutes: Set<Int> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(day.chains.enumerated()), id: \.offset) { index, chain in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Rectangle().fill(colorScheme == .dark ? Theme.cyan : Theme.color(day.colorIndex ?? 0)).frame(width: 7, height: 7)
                        Button {
                            if collapsedRoutes.contains(index) { collapsedRoutes.remove(index) } else { collapsedRoutes.insert(index) }
                        } label: {
                            HStack(spacing: 6) {
                                Text("路线 \(index+1)").font(.subheadline.weight(.semibold))
                                Image(systemName: collapsedRoutes.contains(index) ? "chevron.right" : "chevron.down").font(.caption2)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("route-toggle-\(index)")
                        Text("\(chain.count) 个地点").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("查看") { store.fly(chain.compactMap { id in store.markers.first(where: { $0.id == id })?.coordinates }) }.font(.caption.weight(.semibold)).frame(minHeight: 32)
                    }
                    if !collapsedRoutes.contains(index) {
                        ForEach(Array(chain.enumerated()), id: \.element) { position, id in
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                Button { store.focus(marker) } label: {
                                    HStack(spacing: 10) {
                                        Text("\(position + 1)").font(.caption).foregroundStyle(Theme.muted).frame(width: 18)
                                        PlaceSelectionRow(marker: marker)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("route-\(index)-marker-\(id)")
                                .contextMenu {
                                    Button("从当天移除", systemImage: "minus.circle", role: .destructive) { Task { await store.removeMarker(id, from: day) } }
                                }
                            }
                        }
                    }

                }.contextMenu {
                    Button("编辑顺序", systemImage: "arrow.up.arrow.down") { chainEditor = ChainEditRequest(day: day, index: index, ids: chain) }
                    Button("删除路线", systemImage: "trash", role: .destructive) { deletingChain = index }
                }.padding(14).background(colorScheme == .dark ? Theme.consoleRaised : Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Button { chainEditor = ChainEditRequest(day: day, index: nil, ids: []) } label: { Label("新建路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath") }
                Spacer()
                Button { addingMarkers = true } label: { Label("加入地点", systemImage: "plus") }
            }.font(.caption.weight(.semibold)).frame(minHeight: 36)
            let linked = Set(day.chains.flatMap { $0 })
            if day.markerIds.contains(where: { !linked.contains($0) }) {
                Text("未安排").font(.caption.weight(.medium)).foregroundStyle(Theme.muted)
            }
            ForEach(day.markerIds.filter { !linked.contains($0) }, id: \.self) { id in
                if let marker = store.markers.first(where: { $0.id == id }) {
                    HStack {
                        Button { store.focus(marker) } label: {
                            MarkerRow(marker: marker, subtitle: day.chains.enumerated().filter { $0.element.contains(id) }.map { "路线 \($0.offset+1)" }.joined(separator: " · "))
                        }.buttonStyle(.plain).accessibilityIdentifier("day-marker-\(id)")
                        .contextMenu { Button("从当天移除", systemImage: "minus.circle", role: .destructive) { Task { await store.removeMarker(id, from: day) } } }

                    }
                }
            }
        }
        .sheet(item: $chainEditor) { ChainEditorView(store: store, request: $0) }
        .sheet(isPresented: $addingMarkers) { DayMarkerPicker(store: store, day: day) }
        .alert("日期标题", isPresented: $editingTitle) {
            TextField("例如：梧桐街区漫步", text: $title)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { var copy = day; copy.title = title; _ = await store.updateDay(copy) } }
        }
        .alert("删除当天？", isPresented: $deletingDay) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { Task { _ = await store.perform { try await $0.mutate(AppStore.dayPath(day), method: "DELETE") } } }
        } message: { Text("将移除当天安排并整理剩余日期，地点仍保留在地图上。") }
        .alert("删除路线？", isPresented: Binding(get: { deletingChain != nil }, set: { if !$0 { deletingChain = nil } })) {
            Button("取消", role: .cancel) { deletingChain = nil }
            Button("删除", role: .destructive) { Task {
                if let index = deletingChain, day.chains.indices.contains(index) { var copy = day; copy.chains.remove(at: index); _ = await store.updateDay(copy) }
                deletingChain = nil
            } }
        } message: { Text("保留当天的地点，只删除这条访问顺序。") }
    }
}
struct ChainEditRequest: Identifiable { var id = UUID(); var day: TripDay; var index: Int?; var ids: [String] }
struct ChainEditorView: View {
    @ObservedObject var store: AppStore
    let request: ChainEditRequest
    @Environment(\.dismiss) private var dismiss
    @State private var ids: [String] = []
    @State private var error: String?
    @State private var query = ""
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
                Section("访问顺序") {
                    ForEach(ids, id: \.self) { id in
                        if let marker = store.markers.first(where: { $0.id == id }) { MarkerRow(marker: marker) }
                    }.onMove { from, to in ids.move(fromOffsets: from, toOffset: to) }
                        .onDelete { ids.remove(atOffsets: $0) }
                }
                Section("当天地点") {
                    ForEach(candidates) { marker in
                        Button { ids.append(marker.id) } label: {
                            HStack(spacing: 12) {
                                PlaceSelectionRow(marker: marker)
                                Image(systemName: "plus.circle.fill").foregroundStyle(Theme.cyan)
                            }
                        }.deleteDisabled(true).moveDisabled(true).accessibilityIdentifier("chain-add-marker-\(marker.id)")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.searchable(text: $query, prompt: "搜索当天地点")
                .environment(\.editMode, .constant(.active))
                .navigationTitle(request.index == nil ? "新建路线" : "编辑路线").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task {
                            do {
                                guard let latest = store.trips.first(where: { $0.id == request.day.tripId })?.days.first(where: { $0.id == request.day.id }), latest.chains == request.day.chains else {
                                    throw AppError.message("路线已更新，请关闭后重新编辑")
                                }
                                let updated = try latest.replacingChain(at: request.index, with: ids)
                                guard ids.allSatisfy({ id in store.markers.contains(where: { $0.id == id }) }) else { throw AppError.message("部分地点已被删除，请重新选择") }
                                if await store.updateDay(updated) { dismiss() } else { error = store.errorMessage }
                            } catch { self.error = error.localizedDescription }
                        }}.disabled(store.saving || ids.count < 2)
                    }
                }
        }.onAppear { ids = request.ids }.interactiveDismissDisabled(store.saving)
    }
}
struct PlaceSelectionRow: View {
    let marker: Marker
    var body: some View {
        HStack(spacing: 12) {
            MapMarkerCircle(icon: marker.icon).frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(marker.title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                if let address = marker.content.address, !address.isEmpty {
                    Text(address).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
}
struct DayMarkerPicker: View {
    @ObservedObject var store: AppStore
    let day: TripDay
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var failure: String?
    private var candidates: [Marker] {
        let current = store.trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }) ?? day
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return [] }
        return Array(store.markers.filter {
            !current.markerIds.contains($0.id) &&
            ($0.title.localizedCaseInsensitiveContains(term) || ($0.content.address ?? "").localizedCaseInsensitiveContains(term))
        }.prefix(30))
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("搜索已保存地点", text: $query).autocorrectionDisabled()
                        .submitLabel(.search).accessibilityIdentifier("saved-place-query")
                    if !query.isEmpty {
                        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }
                            .accessibilityLabel("清除搜索")
                    }
                }.padding(14).background(Theme.consoleRaised, in: RoundedRectangle(cornerRadius: 12)).padding(18)
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button { dismiss() } label: {
                        Label("地图选点", systemImage: "map").font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }.buttonStyle(.bordered).padding(.horizontal, 18).accessibilityIdentifier("choose-place-on-map")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(candidates) { marker in
                                Button {
                                    Task {
                                        if await store.addMarker(marker, to: day) { dismiss() }
                                        else { failure = store.errorMessage }
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        PlaceSelectionRow(marker: marker)
                                        Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.cyan)
                                    }.contentShape(Rectangle()).padding(.horizontal, 18).padding(.vertical, 4)
                                }.buttonStyle(.plain).disabled(store.saving).accessibilityIdentifier("day-add-place-\(marker.id)")
                                Divider().padding(.leading, 66)
                            }
                            if candidates.isEmpty { Text("没有可加入的地点").font(.subheadline).foregroundStyle(Theme.muted).padding(24) }
                        }
                    }.scrollDismissesKeyboard(.interactively)
                }
                if let failure { Text(failure).font(.footnote).foregroundStyle(.red).padding(18) }
                if store.saving { ProgressView().padding(12) }
            }.navigationTitle("加入地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PanelCloseToolbarItem(identifier: "close-place-picker") { dismiss() }
                }
        }.presentationDetents([.medium, .large]).presentationDragIndicator(.visible).interactiveDismissDisabled(store.saving)
    }
}
