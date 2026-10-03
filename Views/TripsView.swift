import SwiftUI
import UniformTypeIdentifiers
import UIKit
import Combine

struct TripEditorView: View {
    @ObservedObject var store: AppStore
    let trip: Trip?
    var initial: TripSaveDraft? = nil
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
                        Button {
                            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "请输入旅行名称"; return }
                            guard trip != nil || start.dayString <= end.dayString else { error = "结束日期不能早于开始日期"; return }
                            if trip == nil && end.timeIntervalSince(start) > 366*86400 { error = "一次最多创建 367 天，请缩短日期范围"; return }
                            let value = TripSaveDraft(id: initial?.id ?? UUID(), trip: trip, name: name.trimmingCharacters(in: .whitespacesAndNewlines), start: start, end: end, emoji: emoji)
                            if store.saveTripInBackground(value) { dismiss() }
                            else { error = store.errorMessage }
                        } label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("保存")
                            .disabled(store.saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
        }.onAppear {
            if let initial { name = initial.name; start = initial.start; end = initial.end; emoji = initial.emoji }
            else if let trip { name = trip.name; start = .fromDay(trip.startDate); end = .fromDay(trip.endDate); emoji = trip.emoji ?? "✈️" }
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
    @State private var scheduleEditor: RouteScheduleRequest?
    @State private var editingTitle = false
    @State private var title = ""
    @State private var deletingDay = false
    @State private var deletingChain: Int?
    @State private var nativeRouteFrames: [String: CGRect] = [:]
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
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["\(index)/header": geometry.frame(in: .global)])
                    })
                    .contextMenu {
                        Button("编辑路线", systemImage: "arrow.up.arrow.down") { chainEditor = ChainEditRequest(day: day, index: index, ids: chain) }
                        DestructiveMenuButton(title: "删除路线", systemImage: "trash") { deletingChain = index }
                    }
                    .font(.body)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
                    if !collapsedRoutes.contains(index) {
                        ForEach(chain.enumerated().map { RoutePlaceSlot(markerID: $0.element, position: $0.offset) }) { slot in
                            let id = slot.markerID
                            let position = slot.position
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                VStack(spacing: 0) {
                                    RoutePlaceSelectionButton(store: store, dayID: day.id, routeIndex: index, marker: marker, stop: day.scheduledRoute(at: index)?.stops[position]) {
                                        if let route = day.scheduledRoute(at: index) { openSchedule(route, position: position, transport: false) }
                                    }
                                    if let route = day.scheduledRoute(at: index) {
                                        let stop = route.stops[position]
                                        if let note = stop.note, !note.isEmpty {
                                            Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.leading, 78).padding(.bottom, 5)
                                        }
                                    }

                                    if position + 1 < chain.count {
                                        Group {
                                            if let route = day.scheduledRoute(at: index) {
                                                RouteTransportRow(leg: route.leg(at: position), distance: routeDistance(chain: chain, index: index, position: position + 1)) {
                                                    openSchedule(route, position: position, transport: true)
                                                }.accessibilityIdentifier("route-\(index)-transport-\(position)")
                                            } else if let distance = routeDistance(chain: chain, index: index, position: position + 1) {
                                                HStack(spacing: 8) {
                                                    Rectangle().fill(Theme.routeDividerColor).frame(height: Theme.routeDividerHeight)
                                                    Text(distance).font(.caption).foregroundStyle(.secondary).fixedSize()
                                                    Rectangle().fill(Theme.routeDividerColor).frame(height: Theme.routeDividerHeight)
                                                }.frame(height: 13.5).accessibilityElement(children: .combine)
                                                    .accessibilityIdentifier("route-\(index)-distance-\(position + 1)")
                                            } else { Color.clear.frame(height: 13.5).accessibilityHidden(true) }
                                        }

                                    }
                                }
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["\(index)/\(position)": geometry.frame(in: .global)])
                    })
                                .listRowSeparator(.hidden, edges: .all)
                                .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        makeDayPlaceUnplanned(id)
                                    } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("移出路线").buttonStyle(.automatic).tint(.red).disabled(store.saving)
                                }
                                .onDrag {
                                    guard !store.saving else { return NSItemProvider() }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    return NativePlaceItemProvider(payload: "day-place/" + day.id + "/" + id + "/" + String(index))
                                } preview: {
                                    VStack(spacing: 0) {
                                        RoutePlaceSelectionButton(store: store, dayID: day.id, routeIndex: index, marker: marker, stop: day.scheduledRoute(at: index)?.stops[position])
                                        if let note = day.scheduledRoute(at: index)?.stops[position].note, !note.isEmpty {
                                            Text(note).font(.footnote).foregroundStyle(.secondary).lineLimit(2)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                                .padding(.leading, 78).padding(.bottom, 5)
                                        }
                                    }
                                    .frame(width: nativeRouteFrames["\(index)/\(position)"]?.width)
                                    .background(Color(uiColor: .systemBackground))
                                }

                                .accessibilityAction(named: "移出路线") { makeDayPlaceUnplanned(id) }

                            }
                        }
                    }

                }
            }
            let linked = Set(day.chains.flatMap { $0 })
            let unlinked = day.markerIds.filter { !linked.contains($0) }
            Section {
                    ForEach(unlinked, id: \.self) { id in
                        if let marker = store.markers.first(where: { $0.id == id }) {
                            PlaceSelectionRow(marker: marker)
                                .contentShape(Rectangle())
                                .onTapGesture { store.focus(marker) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityIdentifier("day-marker-\(id)")
                                .background(GeometryReader { geometry in
                                    Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                                })
                                .onDrag {
                                    guard !store.saving else { return NSItemProvider() }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    return NativePlaceItemProvider(payload: "day-place/" + day.id + "/" + id)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                    } label: { Image(systemName: "trash") }
                                    .accessibilityLabel("删除").tint(.red).disabled(store.saving)
                                }
                                .accessibilityAction(named: "从当天移除") {
                                    Task { await store.removeMarker(id, from: day, animated: !reduceMotion) }
                                }
                        }
                    }
                Button { store.beginAddingPlace(to: day) } label: { Label("添加地点", systemImage: "plus").fullRowActionLabel() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("day-search-add-place")
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                    })
            } header: {
                Text("未收入路线").font(.subheadline.weight(.regular)).foregroundStyle(.secondary).textCase(nil)
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: NativeRouteFrames.self, value: ["unplanned": geometry.frame(in: .global)])
                    })
            }
            Section {
                Button { chainEditor = ChainEditRequest(day: day, index: nil, ids: []) } label: {
                    Label("新建路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath").fullRowActionLabel()
                }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            } header: {
                Color.clear.frame(height: 8).accessibilityHidden(true)
            }.font(.body)

            }.listRowBackground(Color(uiColor: .systemBackground))
                .listRowSeparator(.hidden)
        }
        .onPreferenceChange(NativeRouteFrames.self) { nativeRouteFrames = $0 }
        .background(NativePlaceListDrop(frames: nativeRouteFrames, prefix: "day-place/" + day.id + "/", onDrop: { store.finishRouteDrop() }, sourceTargets: Dictionary(uniqueKeysWithValues: day.chains.enumerated().flatMap { route, ids in
            ids.enumerated().map { position, id in (id + "/" + String(route), "\(route)/\(position)") }
        })) { id, route in
            let payload = id.split(separator: "/")
            guard let marker = payload.first else { return }
            let markerID = String(marker)
            if route == "unplanned" { makeDayPlaceUnplanned(markerID, animated: false); return }
            let source = payload.count > 1 ? Int(payload[1]) : nil
            let parts = route.split(separator: "/")
            guard let first = parts.first, let index = Int(first) else { return }
            let position = parts.count > 1 ? Int(parts[1]) : nil
            let insertion = position.map { $0 + (parts.last == "after" ? 1 : 0) }
            moveDayPlace(markerID, from: source, to: index, at: insertion)
        })
        .sheet(item: $chainEditor) { ChainEditorView(store: store, request: $0) }
        .sheet(item: $scheduleEditor) { RouteScheduleEditor(store: store, request: $0) }
        .alert("日期标题", isPresented: $editingTitle) {
            TextField("例如：梧桐街区漫步", text: $title)
            Button("取消", role: .cancel) {}
            Button("保存") { var copy = day; copy.title = title; _ = store.saveDayInBackground(copy) }
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
                latest.removeRoute(at: index)
                if store.saveDayInBackground(latest, animated: !reduceMotion) {
                    collapsedRoutes = Set(collapsedRoutes.filter { $0 != index }.map { $0 > index ? $0 - 1 : $0 })
                }
            }
        } message: { Text("保留当天的地点，只删除这条访问顺序。") }
    }
    private func makeDayPlaceUnplanned(_ id: String, animated: Bool = true) {
        guard let ti = store.trips.firstIndex(where: { $0.id == day.tripId }),
              let di = store.trips[ti].days.firstIndex(where: { $0.id == day.id }),
              !store.saving else { return }
        var current = store.trips[ti].days[di]
        // Keep day membership, remove every route reference so the place becomes isolated.
        current.setRouteOrders(current.chains.map { $0.filter { $0 != id } })
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
        guard !store.saving, current.chains.indices.contains(index),
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

    private func openSchedule(_ route: RouteChain, position: Int, transport: Bool) {
        guard store.canActivateRouteRow, route.stops.indices.contains(position), !transport || route.stops.indices.contains(position + 1) else { return }
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
        guard position > 0, position < chain.count,
              let route = store.displayRoutes.first(where: { $0.id == "\(day.id)|\(index)|\(position)|\(chain[position - 1])|\(chain[position])" }),
              route.isPlanned, let distance = route.distance, distance.isFinite, distance >= 0 else { return nil }
        return distance < 1000 ? "\(Int(distance.rounded())) m" : String(format: "%.1f km", distance / 1000)
    }

}
/// Observe optimistic local membership directly, independently of the parent
/// row's captured position and later route geometry/distance publications.
private struct RoutePlaceSelectionButton: View {
    @ObservedObject var store: AppStore
    let dayID: String
    let routeIndex: Int
    let marker: Marker
    var stop: ChainStop? = nil
    var editSchedule: () -> Void = {}
    private var ordinal: String {
        guard let day = store.trips.lazy.flatMap(\.days).first(where: { $0.id == dayID }),
              day.chains.indices.contains(routeIndex),
              let position = day.chains[routeIndex].firstIndex(of: marker.id) else { return "" }
        return String(position + 1)
    }
    var body: some View {
        if stop == nil {
            Button { if store.canActivateRouteRow { store.focus(marker) } } label: {
                HStack(spacing: 12) {
                    RouteOrdinalLabel(store: store, dayID: dayID, routeIndex: routeIndex, markerID: marker.id)
                        .frame(width: 18).fixedSize(horizontal: false, vertical: true)
                    PlaceSelectionRow(marker: marker)
                }.contentShape(Rectangle())
            }.buttonStyle(.automatic).foregroundStyle(.primary)
                .accessibilityIdentifier("route-\(routeIndex)-marker-\(marker.id)").accessibilityValue(ordinal)
        } else {
        HStack(spacing: 12) {
            RouteOrdinalLabel(store: store, dayID: dayID, routeIndex: routeIndex, markerID: marker.id)
                .frame(width: 18).fixedSize(horizontal: false, vertical: true)
            Button { if store.canActivateRouteRow { store.focus(marker) } } label: {
                MapMarkerCircle(icon: marker.icon).frame(width: 36, height: 36)
            }.buttonStyle(.plain).accessibilityLabel(marker.title)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .top, spacing: 8) {
                    Button { if store.canActivateRouteRow { store.focus(marker) } } label: {
                        Text(marker.title).font(.body).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("route-\(routeIndex)-marker-\(marker.id)")
                        .accessibilityValue(ordinal)
                    if let stop {
                        Button(action: editSchedule) {
                            HStack(spacing: 4) {
                                if stop.summary.isEmpty { Image(systemName: "clock") }
                                Text(stop.summary.isEmpty ? "--:--" : stop.summary).monospacedDigit()
                            }.font(.caption).foregroundStyle(.secondary).fixedSize()
                        }.buttonStyle(.plain).accessibilityLabel("编辑游览安排")
                            .accessibilityIdentifier("route-\(routeIndex)-schedule-\(marker.id)")
                            .accessibilityValue(stop.summary)
                    }
                }
                if let address = marker.content.address, !address.isEmpty {
                    Button { if store.canActivateRouteRow { store.focus(marker) } } label: {
                        Text(address).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(.vertical, 6)
    }
        }
}

/// The dragged cell may stay retained by UIKit while SwiftUI moves its hosting
/// row. Bind the actual numeral to the local snapshot, not to a later host redraw.
private struct RouteOrdinalLabel: UIViewRepresentable {
    let store: AppStore
    let dayID: String
    let routeIndex: Int
    let markerID: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.textColor = .secondaryLabel
        label.accessibilityIdentifier = "route-\(routeIndex)-ordinal-\(markerID)"
        return label
    }
    func updateUIView(_ label: UILabel, context: Context) {
        label.font = .monospacedDigitSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize,
                                               weight: .regular)
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
        return store.addPlaceTripID != nil ? "同时添加到当前旅行" : nil
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
            if old == nil && new != nil { onSearch() }
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
                store.choose(place); store.prepareSearchPlaceAddition(place); onSearch()
            } label: {
                if store.addingPlaceID == place.id { ProgressView().frame(width: 44, height: 44) }
                else { Image(systemName: "plus.circle.fill").font(.title2).frame(width: 44, height: 44) }
            }.buttonStyle(.borderless).disabled(store.saving)
                .accessibilityLabel(day == nil ? "保存地点：\(place.name)" : "加入当天：\(place.name)")
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
    let prefix: String
    var onDrop: () -> Void = {}
    var sourceTargets: [String: String] = [:]
    var onTarget: (String?) -> Void = { _ in }
    let accept: (String, String) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
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
    final class Coordinator: NSObject, UIDropInteractionDelegate, UICollectionViewDropDelegate {
        var parent: NativePlaceListDrop
        weak var host: UIView?
        var dragFrames: [String: CGRect]?
        var nativeRowTargets: [IndexPath: String] = [:]
        private var publishedTarget: String?
        var interaction: UIDropInteraction?
        weak var originalDropDelegate: (any UICollectionViewDropDelegate)?
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
                list.dropDelegate = self; host = list
                return
            }
            let interaction = UIDropInteraction(delegate: self)
            view.addInteraction(interaction); host = view; self.interaction = interaction
        }
        func detach() { if let list = host as? UICollectionView, list.dropDelegate === self { list.dropDelegate = originalDropDelegate }; if let interaction { host?.removeInteraction(interaction) }; interaction = nil; host = nil }
        func target(_ session: UIDropSession) -> String? {
            guard let host, let window = host.window else { return nil }
            let point = session.location(in: window)
            let frames = parent.prefix.hasPrefix("trip-place/") ? parent.frames : (dragFrames ?? parent.frames)
            guard let match = frames.sorted(by: { $0.key.split(separator: "/").count > $1.key.split(separator: "/").count }).first(where: { $0.value.contains(point) }) else { return nil }
            let parts = match.key.split(separator: "/")
            if parts.count == 2, Int(parts[1]) != nil {
                return match.key + (point.y < match.value.midY ? "/before" : "/after")
            }
            return match.key
        }
        func collectionView(_ collectionView: UICollectionView, canHandle session: UIDropSession) -> Bool {
            if dragFrames == nil {
                dragFrames = parent.frames
                nativeRowTargets = [:]
                if let window = collectionView.window {
                    if let pool = parent.frames["unplanned"] {
                        for path in collectionView.indexPathsForVisibleItems {
                            if let cell = collectionView.cellForItem(at: path) {
                                let point = cell.convert(CGPoint(x: cell.bounds.midX, y: cell.bounds.midY), to: window)
                                if pool.contains(point) { nativeRowTargets[path] = "unplanned" }
                            }
                        }
                    }
                    for (key, frame) in parent.frames where key != "unplanned" {
                        let point = collectionView.convert(CGPoint(x: frame.midX, y: frame.midY), from: window)
                        if let path = collectionView.indexPathForItem(at: point) { nativeRowTargets[path] = key }
                    }
                }
            }
            return session.localDragSession != nil && session.canLoadObjects(ofClass: NSString.self)
        }
        /// Every day-place drag uses this resolver, regardless of its source.
        /// Native insertion remains authoritative; live geometry covers missing
        /// indices after scrolling and the card margins/traffic/gaps.
        private func resolvedTarget(_ session: UIDropSession, destination: IndexPath?) -> String? {
            guard parent.prefix.hasPrefix("day-place/"), let host, let window = host.window else {
                return target(session)
            }
            let point = session.location(in: window)
            let bounds = host.convert(host.bounds, to: window)
            if let pool = livePoolTarget(session) { return pool }
            guard bounds.contains(point) else { return nil }
            let geometric = NativeRouteDropGeometry.target(at: point, frames: parent.frames)
            let native = destination.flatMap { insertionTarget(at: $0, session: session) }
            if native == "unplanned" { return "unplanned" }
            if let geometric {
                let route = geometric.split(separator: "/").first
                if let native, native.split(separator: "/").first == route { return native }
                return geometric
            }
            return native ?? target(session)
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
                            withDestinationIndexPath destinationIndexPath: IndexPath?) -> UICollectionViewDropProposal {
            let target = resolvedTarget(session, destination: destinationIndexPath)
            publishTarget(target)
            return UICollectionViewDropProposal(operation: target == nil ? .cancel : .move, intent: parent.prefix.hasPrefix("day-place/") ? .insertAtDestinationIndexPath : .insertIntoDestinationIndexPath)
        }
        private func livePoolTarget(_ session: UIDropSession) -> String? {
            guard let window = host?.window else { return nil }
            let point = session.location(in: window)
            if parent.frames["unplanned"]?.contains(point) == true || dragFrames?["unplanned"]?.contains(point) == true { return "unplanned" }
            // Native insertion pushes the pool below the pointer. Keep its original
            // region eligible, translated with a stable header to account for scrolling.
            if let pool = dragFrames?["unplanned"],
               let anchor = dragFrames?.keys.sorted().first(where: { $0.hasSuffix("/header") }),
               let original = dragFrames?[anchor], let current = parent.frames[anchor],
               pool.offsetBy(dx: current.minX - original.minX, dy: current.minY - original.minY).contains(point) {
                return "unplanned"
            }
            return nil
        }
        private func insertionTarget(at destination: IndexPath, session: UIDropSession) -> String? {
            var path = destination
            if parent.prefix.hasPrefix("day-place/"), let list = host as? UICollectionView,
               destination.section == list.numberOfSections - 2 { return "unplanned" }
            // UIKit reports a final index for moves within the same section,
            // after removing the source. Our model accepts a pre-removal boundary.
            if let payload = localPayload(session) {
                let parts = payload.dropFirst(parent.prefix.count).split(separator: "/")
                if parts.count == 2, let sourceRouteKey = parent.sourceTargets[String(parts[0]) + "/" + String(parts[1])],
                   let source = nativeRowTargets.first(where: { entry in
                       entry.value == sourceRouteKey
                   })?.key, source.section == path.section, source.item < path.item {
                    path = IndexPath(item: path.item + 1, section: path.section)
                }
            }
            guard parent.prefix.hasPrefix("day-place/") else { return nil }
            if let key = nativeRowTargets[path] {
                let parts = key.split(separator: "/")
                return parts.count == 2 && Int(parts[1]) != nil ? key + "/before" : key
            }
            // A drop after the pool's last cell has no destination cell. It still
            // belongs to the pool, including when auto-scroll moved it above the finger.
            if path.item > 0, nativeRowTargets[IndexPath(item: path.item - 1, section: path.section)] == "unplanned" { return "unplanned" }
            // The insertion boundary after the final item has no cell of its own.
            if path.item > 0, let key = nativeRowTargets[IndexPath(item: path.item - 1, section: path.section)],
               let position = key.split(separator: "/").last, Int(position) != nil {
                return key + "/after"
            }
            return nil
        }
        func collectionView(_ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession) {
            originalDropDelegate?.collectionView?(collectionView, dropSessionDidEnd: session)
            publishTarget(nil); dragFrames = nil; nativeRowTargets = [:]
        }
        func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
            guard let target = resolvedTarget(coordinator.session, destination: coordinator.destinationIndexPath) else { return }
            publishTarget(nil)
            acceptDrop(coordinator.session, target: target)
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
            guard let target = resolvedTarget(session, destination: nil) else { return }
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
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                return
            }
            session.loadObjects(ofClass: NSString.self) { objects in
                guard let text = objects.first as? String, text.hasPrefix(prefix) else { return }
                accept(String(text.dropFirst(prefix.count)), target)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }
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
