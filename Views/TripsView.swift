import SwiftUI

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
                        Button { Task {
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
                        }} label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("保存")
                            .disabled(store.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.onAppear {
            if let trip { name = trip.name; start = .fromDay(trip.startDate); end = .fromDay(trip.endDate); emoji = trip.emoji ?? "✈️" }
        }.onChange(of: start) { _, value in
            if trip == nil && end < value { end = value }
        }.interactiveDismissDisabled(store.saving)
    }
}
struct DayContentsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: AppStore
    let day: TripDay
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
            Group {

            ForEach(Array(day.chains.enumerated()), id: \.offset) { index, chain in
                Section {
                    HStack(spacing: 0) {
                        Button {
                            onViewRoute()
                            store.fly(chain.compactMap { id in store.markers.first(where: { $0.id == id })?.coordinates })
                        } label: {
                            HStack {
                                Label {
                                    Text("路线 \(index + 1)").foregroundStyle(.primary)
                                } icon: {
                                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                        .foregroundStyle(Theme.color(day.colorIndex ?? 0))
                                }
                                Spacer(minLength: 8)
                                Text("\(chain.count)个地点").font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("route-view-\(index)")
                        .accessibilityHint("在地图上查看路线")
                        Button {
                            withAnimation(AppMotion.disclosure(reduceMotion: reduceMotion)) {
                                if collapsedRoutes.contains(index) { collapsedRoutes.remove(index) }
                                else { collapsedRoutes.insert(index) }
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.subheadline.weight(.semibold))
                                .rotationEffect(.degrees(collapsedRoutes.contains(index) ? 0 : 90))
                                .frame(width: 48, height: 48)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .fixedSize(horizontal: true, vertical: true)
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("\(collapsedRoutes.contains(index) ? "展开" : "收起")路线 \(index + 1)")
                        .accessibilityValue(collapsedRoutes.contains(index) ? "已收起" : "已展开")
                        .accessibilityIdentifier("route-toggle-\(index)")
                    }
                    .contextMenu {
                        Button("编辑路线", systemImage: "arrow.up.arrow.down") { chainEditor = ChainEditRequest(day: day, index: index, ids: chain) }
                        DestructiveMenuButton(title: "删除路线", systemImage: "trash") { deletingChain = index }
                    }
                    .font(.body)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
                    if !collapsedRoutes.contains(index) {
                        ForEach(Array(chain.enumerated()), id: \.element) { position, id in
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                VStack(spacing: 0) {
                                    Button { store.focus(marker) } label: {
                                        HStack(spacing: 12) {
                                            Text("\(position + 1)").font(.subheadline).monospacedDigit()
                                                .foregroundStyle(.secondary).frame(minWidth: 18)
                                            PlaceSelectionRow(marker: marker)
                                        }.contentShape(Rectangle())
                                    }.buttonStyle(.automatic).foregroundStyle(.primary)
                                        .accessibilityIdentifier("route-\(index)-marker-\(id)")
                                    if position + 1 < chain.count, let distance = routeDistance(chain: chain, index: index, position: position + 1) {
                                        HStack(spacing: 8) {
                                            Rectangle().fill(Theme.routeDividerColor).frame(height: Theme.routeDividerHeight)
                                            Text(distance).font(.caption).foregroundStyle(.secondary).fixedSize()
                                                .background(Color(uiColor: .systemBackground))
                                            Rectangle().fill(Theme.routeDividerColor).frame(height: Theme.routeDividerHeight)
                                        }
                                        .frame(height: 13.5)
                                        .accessibilityElement(children: .combine)
                                        .accessibilityIdentifier("route-\(index)-distance-\(position + 1)")
                                    } else {
                                        Color.clear.frame(height: 13.5).accessibilityHidden(true)
                                    }
                                }
                                .listRowSeparator(.hidden, edges: .all)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                    } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("删除").buttonStyle(.automatic).tint(.red).disabled(store.saving)
                                }
                                .contextMenu {
                                    Button("编辑路线", systemImage: "arrow.up.arrow.down") { chainEditor = ChainEditRequest(day: day, index: index, ids: chain) }
                                    DestructiveMenuButton(title: "从当天移除", systemImage: "minus.circle") { Task { await store.removeMarker(id, from: day, animated: !reduceMotion) } }
                                }
                            }
                        }
                    }

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
                Color.clear.frame(height: 8).accessibilityHidden(true)
            }.font(.body)

            }.listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
        }
        .sheet(item: $chainEditor) { ChainEditorView(store: store, request: $0) }
        .alert("日期标题", isPresented: $editingTitle) {
            TextField("例如：梧桐街区漫步", text: $title)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { var copy = day; copy.title = title; _ = await store.updateDay(copy) } }
        }
        .sheet(isPresented: $deletingDay) { DayDeletionView(store: store, day: day) }
        .alert("删除路线？", isPresented: Binding(get: { deletingChain != nil }, set: { if !$0 { deletingChain = nil } })) {
            Button("取消", role: .cancel) { deletingChain = nil }
            Button("删除", role: .destructive) {
                guard let index = deletingChain else { return }
                deletingChain = nil
                guard var latest = store.trips.first(where: { $0.id == day.tripId })?.days.first(where: { $0.id == day.id }),
                      latest.chains.indices.contains(index), day.chains.indices.contains(index),
                      latest.chains[index] == day.chains[index] else { return }
                latest.chains.remove(at: index)
                if store.saveDayInBackground(latest, animated: !reduceMotion) {
                    collapsedRoutes = Set(collapsedRoutes.filter { $0 != index }.map { $0 > index ? $0 - 1 : $0 })
                }
            }
        } message: { Text("保留当天的地点，只删除这条访问顺序。") }
    }
    private func routeDistance(chain: [String], index: Int, position: Int) -> String? {
        #if DEBUG
        if store.demo, ProcessInfo.processInfo.arguments.contains("--route-distance-preview"), position > 0, position < chain.count {
            return position == 1 ? "850 m" : "1.2 km"
        }
        #endif
        guard position > 0, position < chain.count,
              let route = store.displayRoutes.first(where: { $0.id == "\(day.id)|\(index)|\(position)|\(chain[position - 1])|\(chain[position])" }),
              route.isPlanned, let distance = route.distance, distance.isFinite, distance >= 0 else { return nil }
        return distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
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
                        Button { Task {
                            do {
                                guard let latest = store.trips.first(where: { $0.id == request.day.tripId })?.days.first(where: { $0.id == request.day.id }), latest.chains == request.day.chains else {
                                    throw AppError.message("路线已更新，请关闭后重新编辑")
                                }
                                let updated = try RouteEditSession(day: request.day, index: request.index, ids: ids).applying(to: latest)
                                guard ids.allSatisfy({ id in store.markers.contains(where: { $0.id == id }) }) else { throw AppError.message("部分地点已被删除，请重新选择") }
                                if updated == latest { dismiss(); return }
                                if store.saveDayInBackground(updated) { dismiss() } else { error = store.errorMessage }
                            } catch { self.error = error.localizedDescription }
                        }} label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("保存")
                            .disabled(store.saving || (request.index == nil && ids.count < 2))
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
    private var targetTitle: String { day == nil ? "搜索地点" : "搜索图标" }
    private var targetSubtitle: String? {
        if day != nil { return "同时添加到今日行程" }
        return store.tripPlacesPreview && store.trip != nil ? "同时添加到当前旅行" : nil
    }
    var body: some View {
        ZStack(alignment: .top) {
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
                        if let id { withAnimation(AppMotion.scroll(reduceMotion: reduceMotion)) { reader.scrollTo(id) } }
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
            .background(JourneyToolbarContainerOffset())
            .navigationTitle(targetTitle).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        Text(targetTitle).font(.headline)
                        if let targetSubtitle { Text(targetSubtitle).font(.caption).foregroundStyle(.secondary) }
                    }.accessibilityElement(children: .combine)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button { store.endAddingPlace() } label: {
                        Image(systemName: "chevron.left")
                    }.disabled(store.saving)
                        .accessibilityLabel("返回旅途")
                        .accessibilityIdentifier("close-place-picker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("搜索此区域", systemImage: "magnifyingglass") {
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
        .opacity(compact ? 0 : 1)
        .allowsHitTesting(!compact)
        .accessibilityHidden(compact)
            if compact {
                HStack(spacing: 4) {
                    Button { store.endAddingPlace() } label: {
                        Image(systemName: "chevron.left").font(.system(size: 20))
                            .frame(width: 30, height: 30)
                    }.modifier(JourneyCircleButtonStyle())
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("返回旅途").accessibilityIdentifier("close-place-picker")
                        .frame(width: 88, alignment: .leading)
                    VStack(spacing: 3) {
                        Text(targetTitle).font(.title3.weight(.semibold)).foregroundStyle(Color(uiColor: .label)).lineLimit(1)
                        if let targetSubtitle { Text(targetSubtitle).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)) }
                    }.frame(maxWidth: .infinity)
                    Button {
                        searched = true; onSearch(); Task { await store.search() }
                    } label: {
                        Image(systemName: "magnifyingglass").font(.system(size: 20))
                            .frame(width: 44, height: 44)
                    }.accessibilityLabel("搜索此区域")
                        .disabled(store.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.searching)
                        .frame(width: 88, alignment: .trailing)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .frame(height: JourneyPresentation.compactHeight)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("compact-search-controls")
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
