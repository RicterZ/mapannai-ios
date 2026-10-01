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

                        }.padding(.vertical, 6).contentShape(Rectangle())
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
    @State private var start = Date.now
    @State private var end = Date.now
    @State private var emoji = "✈️"
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Menu {
                            ForEach(["✈️", "🏍️", "🚗", "🚆", "🚲", "🥾", "🏕️", "🏖️", "🏔️", "🍂"], id: \.self) { symbol in
                                Button { emoji = symbol } label: {
                                    if emoji == symbol { Label(symbol, systemImage: "checkmark") }
                                    else { Text(symbol) }
                                }.accessibilityIdentifier("trip-icon-option-\(symbol)")
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(emoji).font(.system(size: 22))
                                Image(systemName: "chevron.down").font(.caption2)
                            }.frame(width: 44, height: 44)
                        }.buttonStyle(.borderless).accessibilityLabel("旅行图标：\(emoji)")
                            .accessibilityIdentifier("trip-icon-picker")
                        TextField("旅行名称", text: $name).font(.body).frame(minHeight: 44)
                            .accessibilityIdentifier("trip-name-field")
                    }.transaction { $0.animation = nil }
                }
                Section("日期") {
                    DatePicker("开始日期", selection: $start, displayedComponents: .date)
                        .accessibilityIdentifier("trip-start-date")
                    if trip == nil { DatePicker("结束日期", selection: $end, in: start..., displayedComponents: .date) }
                    else { Text("修改开始日期会保留天数并顺移每日安排。增减天数在每日行程中操作。").font(.caption).foregroundStyle(.secondary) }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }.scrollDismissesKeyboard(.interactively)
                .navigationTitle(trip == nil ? "创建旅行" : "编辑旅行").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.saving) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task {
                            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请输入旅行名称"; return }
                            guard trip != nil || start.dayString <= end.dayString else { error = "结束日期不能早于开始日期"; return }
                            // Bound creation to protect against accidental multi-year ranges.
                            if trip == nil && end.timeIntervalSince(start) > 366*86400 { error = "一次最多创建 367 天，请缩短日期范围"; return }
                            let ok = await store.perform { client in
                                var body: [String: Any] = ["name": name.trimmingCharacters(in: .whitespacesAndNewlines), "startDate": start.dayString, "emoji": emoji]
                                if let trip { try await client.mutate("trips/\(APIClient.id(trip.id))", method: "PUT", body: body) }
                                else {
                                    body["endDate"] = end.dayString
                                    let created: Trip = try await client.request("trips", method: "POST", body: body)
                                    if emoji != "✈️" { try await client.mutate("trips/\(APIClient.id(created.id))", method: "PUT", body: ["emoji": emoji]) }
                                }
                            }
                            if ok { dismiss() } else { error = store.errorMessage }
                        }}.disabled(store.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.onAppear {
            if let trip { name = trip.name; start = .fromDay(trip.startDate); end = .fromDay(trip.endDate); emoji = trip.emoji ?? "✈️" }
        }.onChange(of: start) { _, value in
            if trip == nil && end < value { end = value }
        }.interactiveDismissDisabled(store.saving)
    }
}
struct DayContentsView<SearchContent: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: AppStore
    let day: TripDay
    @ViewBuilder var searchContent: () -> SearchContent
    var onViewRoute: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @State private var chainEditor: ChainEditRequest?
    @State private var editingTitle = false
    @State private var title = ""
    @State private var deletingDay = false
    @State private var deletingChain: Int?
    @State private var collapsedRoutes: Set<Int> = []
    var body: some View {
        List {

            ForEach(Array(day.chains.enumerated()), id: \.offset) { index, chain in
                Section {
                    DisclosureGroup(isExpanded: Binding(
                        get: { !collapsedRoutes.contains(index) },
                        set: { if $0 { collapsedRoutes.remove(index) } else { collapsedRoutes.insert(index) } }
                    )) {} label: {
                        HStack {
                            Label {
                                Text("路线 \(index + 1)").foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                    .foregroundStyle(Theme.color(day.colorIndex ?? 0))
                            }
                            Spacer(minLength: 8)
                            Text("\(chain.count)个地点").font(.subheadline).foregroundStyle(.secondary)
                        }.font(.body).accessibilityIdentifier("route-toggle-\(index)")
                    }
                    if !collapsedRoutes.contains(index) {
                        Button {
                            onViewRoute()
                            store.fly(chain.compactMap { id in store.markers.first(where: { $0.id == id })?.coordinates })
                        } label: { Label("查看路线", systemImage: "map").fullRowActionLabel() }
                            .buttonStyle(.plain).foregroundStyle(Theme.accent)
                            .accessibilityIdentifier("route-view-\(index)")
                        ForEach(Array(chain.enumerated()), id: \.element) { position, id in
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                Button { store.focus(marker) } label: {
                                    HStack(spacing: 12) {
                                        Text("\(position + 1)").font(.subheadline).monospacedDigit()
                                            .foregroundStyle(.secondary).frame(minWidth: 18)
                                        PlaceSelectionRow(marker: marker)
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.automatic).foregroundStyle(.primary).accessibilityIdentifier("route-\(index)-marker-\(id)")
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button {
                                            Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                        } label: { Image(systemName: "trash") }
                                        .accessibilityLabel("删除").buttonStyle(.automatic).tint(.red).disabled(store.saving)
                                    }
                                    .contextMenu {
                                        DestructiveMenuButton(title: "从当天移除", systemImage: "minus.circle") { Task { await store.removeMarker(id, from: day, animated: !reduceMotion) } }
                                    }
                            }
                        }
                    }

                }.contextMenu {
                    Button("编辑顺序", systemImage: "arrow.up.arrow.down") { chainEditor = ChainEditRequest(day: day, index: index, ids: chain) }
                    DestructiveMenuButton(title: "删除路线", systemImage: "trash") { deletingChain = index }
                }
            }
            let linked = Set(day.chains.flatMap { $0 })
            let unlinked = day.markerIds.filter { !linked.contains($0) }
            if !unlinked.isEmpty {
                Section {
                    ForEach(unlinked, id: \.self) { id in
                        if let marker = store.markers.first(where: { $0.id == id }) {
                            Button { store.focus(marker) } label: { PlaceSelectionRow(marker: marker) }
                                .buttonStyle(.plain).accessibilityIdentifier("day-marker-\(id)")
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                    } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("删除").tint(.red).disabled(store.saving)
                                }
                                .contextMenu {
                                    DestructiveMenuButton(title: "从当天移除", systemImage: "minus.circle") { Task { await store.removeMarker(id, from: day, animated: !reduceMotion) } }
                                }
                        }
                    }
                }
            }
            Section {
                Button { chainEditor = ChainEditRequest(day: day, index: nil, ids: []) } label: {
                    Label("新建路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath").fullRowActionLabel()
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                Button { store.beginAddingPlace(to: day) } label: { Label("添加地点", systemImage: "plus").fullRowActionLabel() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("day-search-add-place")
            } header: {
                Color.clear.frame(height: 16).accessibilityHidden(true)
            }.font(.body)

        }
        .sheet(item: $chainEditor) { ChainEditorView(store: store, request: $0) }
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
    var onInput: () -> Void = {}
    var onSearch: () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searched = false
    private var targetTitle: String {
        guard let day else { return "搜索地点" }
        let trip = store.trips.first { $0.id == day.tripId }
        let number = (trip?.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id } ?? 0) + 1
        return "添加到第\(number)天"
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                NativePlaceSearchBar(text: $store.searchText, searching: store.searching, onSearch: {
                    searched = true; onSearch()
                    Task { await store.search() }
                }, onClear: { store.clearSearch(); searched = false }, onBeginEditing: onInput)
                .frame(height: 56).padding(.horizontal, 8)
                ScrollViewReader { reader in
                List {
                    if store.searching { ProgressView("搜索中…") }
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
                            Button { store.choose(place); onSearch() } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(place.name).foregroundStyle(.primary)
                                        if !place.address.isEmpty { Text(place.address).font(.footnote).foregroundStyle(.secondary) }
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("add-place-result-\(place.id)")
                            addButton(place)
                        }
                        }.id(place.id)
                        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                    SearchPaginationFooter(store: store)
                    }
                }.listStyle(.insetGrouped).scrollContentBackground(.hidden).contentMargins(.top, 8, for: .scrollContent)
                    .scrollDismissesKeyboard(.interactively)
                    .accessibilityIdentifier("add-place-results")
                    .onChange(of: store.selectedSearchPlaceID) { _, id in
                        if let id { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { reader.scrollTo(id) } }
                    }
                }
            }
            .opacity(compact ? 0 : 1)
            .allowsHitTesting(!compact)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let error = store.addPlaceError {
                    Text(error).font(.footnote).foregroundStyle(.red).padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
                }
            }
            .modifier(JourneyNavigationBackground())
            .background(JourneyToolbarContainerOffset(offset: compact ? -3 : 0))
            .navigationTitle(targetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(targetTitle).font(.headline)
                        if let day { Text(day.date).font(.caption).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) { store.endAddingPlace() } } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(store.saving)
                        .accessibilityLabel("返回旅途")
                        .accessibilityIdentifier("close-place-picker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("搜索此区域", systemImage: "arrow.clockwise") {
                        searched = true; onSearch(); Task { await store.search() }
                    }.disabled(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.searching)
                }
            }
            .navigationDestination(isPresented: Binding(get: { store.draft != nil }, set: {
                if !$0 { store.draft = nil; store.editingSearchPlaceID = nil }
            })) {
                if let draft = store.draft {
                    MarkerEditorView(store: store, initial: draft, embedded: true, onSaved: onSearch)
                        .id(draft.id)
                }
            }
        }
        .onChange(of: store.draft?.id) { old, new in
            if old == nil && new != nil { onInput() }
            else if old != nil && new == nil { onSearch() }
        }
        .accessibilityIdentifier("add-place-search-panel")
    }
    @ViewBuilder private func addButton(_ place: Place) -> some View {
        if store.isPlaceAdded(place) {
            Label(day == nil ? "已保存" : "已加入", systemImage: "checkmark").font(.caption).foregroundStyle(.secondary)
                .accessibilityIdentifier("place-added-\(place.id)")
        } else {
            Button {
                store.choose(place); store.prepareSearchPlaceAddition(place); onInput()
            } label: {
                if store.addingPlaceID == place.id { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }.buttonStyle(.borderless).disabled(store.saving)
                .accessibilityLabel(day == nil ? "保存地点：\(place.name)" : "加入当天：\(place.name)")
                .accessibilityIdentifier("add-search-place-\(place.id)")
        }
    }
}
