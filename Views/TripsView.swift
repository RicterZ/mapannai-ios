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
struct DayContentsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: AppStore
    let day: TripDay
    var onViewRoute: () -> Void = {}
    @Environment(\.colorScheme) private var colorScheme
    @State private var draggedID: String?
    @State private var dragPoint = CGPoint.zero
    @State private var dragAnchor = CGPoint.zero
    @State private var dragSlots: [CGFloat] = []
    @State private var listFrame = CGRect.zero
    @State private var rowFrames: [String: CGRect] = [:]
    private var editing: RouteEditSession? { store.routeEdit?.day.id == day.id ? store.routeEdit : nil }
    private var visibleChains: [[String]] {
        var chains = day.chains
        if let editing {
            if let index = editing.index, chains.indices.contains(index) { chains[index] = editing.ids }
            else if editing.index == nil { chains.append(editing.ids) }
        }
        return chains
    }
    @State private var editingTitle = false
    @State private var title = ""
    @State private var deletingDay = false
    @State private var deletingChain: Int?
    @State private var collapsedRoutes: Set<Int> = []
    var body: some View {
        List {

            ForEach(Array(visibleChains.enumerated()), id: \.offset) { index, chain in
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
                        .disabled(editing != nil)
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
                        .disabled(editing?.slot == index)
                    }
                    .contextMenu {
                        Button("编辑顺序", systemImage: "arrow.up.arrow.down") { beginEditing(index) }
                        DestructiveMenuButton(title: "删除路线", systemImage: "trash") { deletingChain = index }.disabled(editing != nil || store.saving)
                    }
                    .font(.body)
                    .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 8))
                    if !collapsedRoutes.contains(index) || editing?.slot == index {
                        ForEach(Array(chain.enumerated()), id: \.element) { position, id in
                            if let marker = store.markers.first(where: { $0.id == id }) {
                                routeRow(marker, position: position, index: index)

                            }
                        }
                    }
                    if editing?.slot == index {
                        let candidates = day.markerIds.filter { !chain.contains($0) }
                        if !candidates.isEmpty {
                            Menu {
                                ForEach(candidates, id: \.self) { id in
                                    if let marker = store.markers.first(where: { $0.id == id }) {
                                        Button(marker.title) { store.routeEdit?.ids.append(id) }
                                    }
                                }
                            } label: { Label("添加当天地点", systemImage: "plus.circle").fullRowActionLabel() }
                            .accessibilityIdentifier("route-add-place")
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
                Button { store.beginRouteEditing(day, index: nil) } label: {
                    Label("新建路线", systemImage: "point.topleft.down.to.point.bottomright.curvepath").fullRowActionLabel()
                }.buttonStyle(.plain).foregroundStyle(Theme.accent).disabled(editing != nil || store.saving)
                Button { store.beginAddingPlace(to: day) } label: { Label("添加地点", systemImage: "plus").fullRowActionLabel() }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent).accessibilityIdentifier("day-search-add-place").disabled(editing != nil || store.saving)
            } header: {
                Color.clear.frame(height: 16).accessibilityHidden(true)
            }.font(.body)

        }
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RouteListFrame.self, value: geometry.frame(in: .global))
        })
        .onPreferenceChange(RouteListFrame.self) { listFrame = $0 }
        .onPreferenceChange(RouteRowFrames.self) { rowFrames = $0 }
        .background(RouteDragRecognizer(
            accepts: { point in
                !store.saving && visibleChains.enumerated().contains { index, ids in
                    (editing == nil || editing?.slot == index) && ids.contains { rowFrames["\(index):\($0)"]?.contains(point) == true }
                }
            },
            onChange: handleRouteDrag
        ))
        .overlay(alignment: .topLeading) {
            if let draggedID, let marker = store.markers.first(where: { $0.id == draggedID }), let editing,
               let frame = rowFrames["\(editing.slot):\(draggedID)"] {
                HStack(spacing: 12) {
                    Image(systemName: "minus.circle.fill").foregroundStyle(.red)
                    PlaceSelectionRow(marker: marker)
                    Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .frame(width: frame.width, height: frame.height)
                .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.16), radius: 8, y: 4)
                .position(x: dragPoint.x - listFrame.minX, y: dragPoint.y - listFrame.minY)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .onChange(of: editing == nil) { _, ended in if ended { draggedID = nil } }
        .onDisappear { draggedID = nil }
        .alert("日期标题", isPresented: $editingTitle) {
            TextField("例如：梧桐街区漫步", text: $title)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { var copy = day; copy.title = title; _ = await store.updateDay(copy) } }
        }
        .sheet(isPresented: $deletingDay) { DayDeletionView(store: store, day: day) }
        .alert("删除路线？", isPresented: Binding(get: { deletingChain != nil }, set: { if !$0 { deletingChain = nil } })) {
            Button("取消", role: .cancel) { deletingChain = nil }
            Button("删除", role: .destructive) { Task {
                if let index = deletingChain, day.chains.indices.contains(index) { var copy = day; copy.chains.remove(at: index); _ = store.saveDayInBackground(copy) }
                deletingChain = nil
            } }
        } message: { Text("保留当天的地点，只删除这条访问顺序。") }
    }
    private func beginEditing(_ index: Int) {
        withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) {
            store.beginRouteEditing(day, index: index)
            collapsedRoutes.remove(index)
        }
    }
    private func routeRow(_ marker: Marker, position: Int, index: Int) -> some View {
        let active = editing?.slot == index
        let key = "\(index):\(marker.id)"
        return HStack(spacing: 12) {
            if active {
                Button {
                    withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) {
                        store.routeEdit?.ids.removeAll { $0 == marker.id }
                    }
                } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red).frame(width: 32, height: 44) }
                .buttonStyle(.borderless).accessibilityLabel("从路线移除\(marker.title)")
                .accessibilityIdentifier("route-remove-\(marker.id)")
            } else {
                Text("\(position + 1)").font(.subheadline).monospacedDigit().foregroundStyle(.secondary).frame(minWidth: 18)
            }
            Button { if editing == nil { store.focus(marker) } } label: { PlaceSelectionRow(marker: marker) }
                .buttonStyle(.plain).foregroundStyle(.primary)
                .accessibilityIdentifier("route-\(index)-marker-\(marker.id)")
            if active {
                Image(systemName: "line.3.horizontal").foregroundStyle(.secondary).frame(width: 32, height: 44)
                    .accessibilityLabel("拖动调整顺序")
            }
        }
        .contentShape(Rectangle())
        .background(GeometryReader { geometry in
            Color.clear.preference(key: RouteRowFrames.self, value: [key: geometry.frame(in: .global)])
        })
        .opacity(draggedID == marker.id && active ? 0 : 1)
        .accessibilityAction(named: "编辑顺序") { beginEditing(index) }
        .accessibilityAction(named: "上移") { moveAccessible(marker.id, index: index, offset: -1) }
        .accessibilityAction(named: "下移") { moveAccessible(marker.id, index: index, offset: 1) }
    }
    private func handleRouteDrag(_ state: UIGestureRecognizer.State, _ point: CGPoint, _ scrollDelta: CGFloat) {
        if state == .began {
            guard let index = visibleChains.indices.first(where: { index in
                (editing == nil || editing?.slot == index) && visibleChains[index].contains { rowFrames["\(index):\($0)"]?.contains(point) == true }
            }), let id = visibleChains[index].first(where: { rowFrames["\(index):\($0)"]?.contains(point) == true }),
               let frame = rowFrames["\(index):\(id)"] else { return }
            beginEditing(index)
            draggedID = id
            dragSlots = visibleChains[index].compactMap { rowFrames["\(index):\($0)"]?.midY }.sorted()
            dragAnchor = CGPoint(x: frame.midX - point.x, y: frame.midY - point.y)
            dragPoint = CGPoint(x: frame.midX, y: frame.midY)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else if state == .changed, let id = draggedID, let editing {
            dragPoint = CGPoint(x: point.x + dragAnchor.x, y: point.y + dragAnchor.y)
            let centers = dragSlots.map { $0 - scrollDelta }
            if centers.count == editing.ids.count,
               let target = centers.indices.min(by: { abs(centers[$0] - dragPoint.y) < abs(centers[$1] - dragPoint.y) }),
               editing.ids[target] != id {
                withAnimation(AppMotion.listMutation(reduceMotion: reduceMotion)) { store.routeEdit?.move(id, to: editing.ids[target]) }
            }
        } else if state == .ended || state == .cancelled || state == .failed {
            draggedID = nil
        }
    }
    private func moveAccessible(_ id: String, index: Int, offset: Int) {
        beginEditing(index)
        guard let edit = editing, edit.slot == index, let position = edit.ids.firstIndex(of: id), edit.ids.indices.contains(position + offset) else { return }
        store.routeEdit?.move(id, to: edit.ids[position + offset])
    }

}
/// Keep one recognizer alive while SwiftUI inserts edit controls and reorders cells.
/// Touch filtering confines this window-level recognizer to this list's route rows.
private struct RouteDragRecognizer: UIViewRepresentable {
    var accepts: (CGPoint) -> Bool
    var onChange: (UIGestureRecognizer.State, CGPoint, CGFloat) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> Anchor {
        let view = Anchor()
        view.isUserInteractionEnabled = false
        view.onWindow = { [weak coordinator = context.coordinator] view in coordinator?.attach(view) }
        context.coordinator.anchor = view
        return view
    }
    func updateUIView(_ view: Anchor, context: Context) { context.coordinator.parent = self }
    static func dismantleUIView(_ view: Anchor, coordinator: Coordinator) { coordinator.detach() }
    final class Anchor: UIView {
        var onWindow: ((Anchor) -> Void)?
        override func didMoveToWindow() { super.didMoveToWindow(); onWindow?(self) }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: RouteDragRecognizer
        weak var anchor: Anchor?
        weak var scroll: UIScrollView?
        var displayLink: CADisplayLink?
        var previousPanEnabled: Bool?
        var manualScrollDelta: CGFloat = 0
        var activeNotification: NSObjectProtocol?
        var lastTimestamp: CFTimeInterval = 0
        lazy var recognizer: UILongPressGestureRecognizer = {
            let value = UILongPressGestureRecognizer(target: self, action: #selector(changed))
            value.minimumPressDuration = 0.35; value.allowableMovement = 12
            value.delegate = self; value.cancelsTouchesInView = true
            return value
        }()
        init(_ parent: RouteDragRecognizer) {
            self.parent = parent
            super.init()
            activeNotification = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                self.recognizer.isEnabled = false
                self.stopScrolling()
                self.recognizer.isEnabled = true
            }
        }
        deinit { if let activeNotification { NotificationCenter.default.removeObserver(activeNotification) } }
        func attach(_ view: Anchor) {
            if recognizer.view !== view.window { detach(); view.window?.addGestureRecognizer(recognizer) }
        }
        func detach() {
            stopScrolling()
            if recognizer.state == .began || recognizer.state == .changed { parent.onChange(.cancelled, .zero, manualScrollDelta) }
            recognizer.view?.removeGestureRecognizer(recognizer)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let anchor, anchor.window != nil, anchor.bounds.contains(touch.location(in: anchor)), parent.accepts(touch.location(in: anchor.window)) else { return false }
            var ancestor = touch.view
            while let view = ancestor {
                if let candidate = view as? UIScrollView { scroll = candidate; break }
                ancestor = view.superview
            }
            return true
        }
        // SwiftUI's button/collection recognizers must not cancel the long press.
        // Once it begins, suspend only the scroll pan until release.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func changed() {
            guard let anchor else { return }
            if recognizer.state == .began { manualScrollDelta = 0 }
            parent.onChange(recognizer.state, recognizer.location(in: anchor.window), manualScrollDelta)
            if recognizer.state == .began {
                previousPanEnabled = scroll?.panGestureRecognizer.isEnabled
                scroll?.panGestureRecognizer.isEnabled = false
                let link = CADisplayLink(target: self, selector: #selector(tick))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 20, maximum: 30, preferred: 30)
                displayLink = link; lastTimestamp = 0; link.add(to: .main, forMode: .common)
            } else if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed { stopScrolling() }
        }
        @objc func tick(_ link: CADisplayLink) {
            guard let anchor, let scroll, recognizer.state == .began || recognizer.state == .changed else { stopScrolling(); return }
            let elapsed = lastTimestamp == 0 ? 0 : min(0.05, link.timestamp - lastTimestamp)
            lastTimestamp = link.timestamp
            let y = recognizer.location(in: scroll).y - scroll.bounds.minY
            let top = scroll.adjustedContentInset.top, bottom = scroll.bounds.height - scroll.adjustedContentInset.bottom
            let speed: CGFloat = y < top + 48 ? -240 : y > bottom - 48 ? 240 : 0
            guard speed != 0 else { return }
            let minimum = -scroll.adjustedContentInset.top
            let maximum = max(minimum, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let offset = min(maximum, max(minimum, scroll.contentOffset.y + speed * elapsed))
            guard offset != scroll.contentOffset.y else { return }
            manualScrollDelta += offset - scroll.contentOffset.y
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: offset), animated: false)
            parent.onChange(.changed, recognizer.location(in: anchor.window), manualScrollDelta)
        }
        func stopScrolling() {
            displayLink?.invalidate(); displayLink = nil
            if let previousPanEnabled { scroll?.panGestureRecognizer.isEnabled = previousPanEnabled }
            previousPanEnabled = nil; scroll = nil
        }
    }
}
private struct RouteListFrame: PreferenceKey {
    static var defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
private struct RouteRowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
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
                        if let day { Text(day.date).font(.caption).foregroundStyle(.secondary) }
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
                        if let day { Text(day.date).font(.caption).foregroundStyle(Color(uiColor: .secondaryLabel)) }
                    }.frame(maxWidth: .infinity)
                    Button {
                        searched = true; onSearch(); Task { await store.search() }
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 20))
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
