import SwiftUI
import CoreLocation

struct HomeView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    @State private var showSettings = false
    @State private var showDates = false
    @State private var editingTrip: Trip?
    @State private var editingDayTitle = false
    @State private var dayTitle = ""
    @State private var deletingPanelDay = false
    @State private var expanded = true
    @State private var sheetDetent: ItineraryDetent = .half
    @State private var sheetDrag: CGFloat = 0
    @ScaledMetric(relativeTo: .headline) private var panelTitleLineHeight: CGFloat = 22
    @StateObject private var location = LocationPermission()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let layout = MapLayout(width: proxy.size.width, height: proxy.size.height,
                                   regularWidth: horizontalSizeClass == .regular, expanded: expanded,
                                   sheetHeight: store.draft != nil && !store.draftExpanded ? proxy.size.height * 0.5 : sheetDetent.height(in: proxy.size.height))
            mapContent(layout: layout, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom, leftInset: proxy.safeAreaInsets.leading)
                .onAppear { store.mapViewportInsets = layout.insets }
                .onChange(of: layout.insets) { _, insets in store.mapViewportInsets = insets }
                .onChange(of: store.selectedMarker?.id) { _, markerID in
                    guard markerID != nil else { return }
                    showDates = false
                    // Reveal the map before the marker sheet covers the lower planning surface.
                    if !layout.usesSidebar {
                        sheetDrag = 0
                        sheetDetent = .half
                    }
                }
        }
        .sheet(item: $editingTrip) { TripEditorView(store: store, trip: $0).presentationDragIndicator(.visible) }
        .alert("删除当天？", isPresented: $deletingPanelDay) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) {
                Task { if let day = store.day { _ = await store.perform { try await $0.mutate(AppStore.dayPath(day), method: "DELETE") } } }
            }
        } message: { Text("删除当天安排，保留地图地点。") }
        .alert("日期标题", isPresented: $editingDayTitle) {
            TextField("标题", text: $dayTitle)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { if var day = store.day { day.title = dayTitle; _ = await store.updateDay(day) } } }
        }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, store: store).presentationDragIndicator(.visible) }
        .sheet(item: $store.selectedMarker) { marker in MarkerDetailView(store: store, marker: marker).presentationDragIndicator(.visible) }
        .sheet(item: $store.draft) { draft in
            MarkerEditorView(store: store, initial: draft).id(draft.id)
                .presentationDetents([.medium, .large], selection: Binding(
                    get: { store.draftExpanded ? .large : .medium },
                    set: { store.draftExpanded = $0 == .large }))
                .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                .presentationDragIndicator(.visible)
        }
        .onChange(of: store.draft?.id) { old, new in
            if new != nil, store.selectedSearchPlaceID != nil { sheetDetent = .compact }
            else if old != nil, new == nil, !store.searchResults.isEmpty { sheetDetent = .half }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .confirmationDialog("选择路线所属日期", isPresented: Binding(get: { !store.routeCandidates.isEmpty }, set: { if !$0 { store.routeCandidates = [] } }), titleVisibility: .visible) {
            ForEach(store.routeCandidates) { route in
                Button(store.trips.first(where: { $0.id == route.tripID })?.days.first(where: { $0.id == route.dayID })?.label ?? "日期") {
                    store.selectRoute(route); store.routeCandidates = []
                }
            }
        }
        .onChange(of: settings.planning) { _, _ in store.rebuildRoutes() }
        .onChange(of: settings.mode) { _, _ in store.rebuildRoutes() }
    }

    private func mapContent(layout: MapLayout, topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MapSurface(store: store, settings: settings, onOpenSettings: { showSettings = true }).ignoresSafeArea()
            if layout.usesSidebar {
                HStack(spacing: 0) {
                    if expanded {
                        workspacePanel(topInset: topInset, bottomInset: bottomInset, leftInset: leftInset)
                            .frame(width: layout.sidebarWidth + leftInset, height: layout.height + topInset + bottomInset)
                            .background(.white)
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink.opacity(0.08)).frame(width: 1) }
                            .accessibilityElement(children: .contain).accessibilityIdentifier("landscape-itinerary-sidebar")
                            .offset(x: -leftInset, y: -topInset)
                    } else {
                        Button { togglePanel() } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 20)).frame(width: 48, height: 48)
                                .softSurface(fill: Theme.console)
                        }.accessibilityLabel("展开行程").padding(.leading, 16).padding(.top, 72).frame(maxHeight: .infinity, alignment: .top)
                    }
                    Spacer(minLength: 0)
                }.frame(width: layout.width, height: layout.height, alignment: .topLeading)
                locationButton.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 20).padding(.bottom, 20)
            } else {
                phonePanel(layout: layout, topInset: topInset, bottomInset: bottomInset)
                    .overlay(alignment: .topTrailing) {
                        if sheetDetent != .full {
                            locationButton.padding(.trailing, 20).offset(y: -60)
                        }
                    }
                    .frame(height: layout.height, alignment: .bottom).offset(y: bottomInset)
            }
            if layout.usesSidebar || sheetDetent != .full {
                navigationCapsules.padding(.horizontal, 16).padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if showDates, let trip = store.trip {
                Color.black.opacity(0.08).ignoresSafeArea().contentShape(Rectangle())
                    .onTapGesture { showDates = false }.accessibilityLabel("关闭日期选择")
                dateDropdown(trip).frame(width: min(layout.width - 32, 196))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.top, 64)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(2)
            }
        }
        .onChange(of: store.tripID) { _, _ in showDates = false }
    }

    @ViewBuilder private var navigationCapsules: some View {
        if let trip = store.trip {
            HStack(spacing: 8) {
                Button { showDates = false; store.select(trip: trip, focus: false) } label: {
                    Text(trip.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 14).frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(Theme.text).accessibilityIdentifier("trip-breadcrumb")
                Text("›").foregroundStyle(Theme.muted)
                Button { withAnimation(.easeOut(duration: 0.15)) { showDates.toggle() } } label: {
                    HStack(spacing: 6) {
                        Text(store.day.map { "第\(dayNumber($0))天" } ?? "总览 · 共\(trip.days.count)天")
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        if let day = store.day {
                            Text(shortDate(day.date)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }.frame(height: 44)
                }.buttonStyle(.plain).foregroundStyle(Theme.cyan).accessibilityIdentifier("date-selector").accessibilityLabel("选择日期")
                Button { showDates = false; store.select(trip: nil, focus: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 28, height: 28).background(Theme.consoleRaised, in: Circle())
                        .frame(width: 36, height: 44)
                }.accessibilityLabel("退出旅行").accessibilityIdentifier("exit-journey")
            }.padding(.trailing, 6).background(.white, in: Capsule())
                .shadow(color: Theme.ink.opacity(0.08), radius: 8, y: 3)
                .accessibilityElement(children: .contain).accessibilityIdentifier("journey-navigation")
        }
    }

    private func dateDropdown(_ trip: Trip) -> some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(trip.days.sorted { $0.date < $1.date }) { day in
                    dateOption(title: "第\(dayNumber(day))天",
                               subtitle: shortDate(day.date),
                               selected: store.dayID == day.id, identifier: "date-option-\(day.id)") {
                        store.select(trip: trip, day: day)
                    }
                }
            }.padding(8)
        }.frame(maxHeight: 340).fixedSize(horizontal: false, vertical: true)
            .background(.white, in: RoundedRectangle(cornerRadius: 18))
            .shadow(color: Theme.ink.opacity(0.15), radius: 16, y: 6)
            .accessibilityIdentifier("date-dropdown")
    }
    private func dateOption(title: String, subtitle: String?, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button { action(); showDates = false } label: {
            HStack(spacing: 10) {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
                Spacer(minLength: 8)
                if selected { Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.cyan) }
            }.padding(12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(selected ? Theme.consoleRaised : .white, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityIdentifier(identifier)
    }

    private func dayNumber(_ day: TripDay) -> Int {
        (store.trip?.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id } ?? 0) + 1
    }
    private func shortDate(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3, let month = Int(parts[1]), let day = Int(parts[2]) else { return date }
        return "\(month)月\(day)日"
    }
    private var panelTitle: String {
        if let day = store.day { return "第\(dayNumber(day))天" }
        return store.trip?.name ?? "旅途"
    }
    private var panelInfo: String {
        if let day = store.day {
            return [day.title?.isEmpty == false ? day.title : nil, "\(day.markerIds.count)个地点"].compactMap { $0 }.joined(separator: " · ")
        }
        if let trip = store.trip { return "\(shortDate(trip.startDate)) – \(shortDate(trip.endDate)) · \(trip.days.count)天" }
        return "\(store.trips.count)个旅行"
    }
    private func panelHeading(compact: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(panelTitle).font(.headline).foregroundStyle(Theme.text).lineLimit(1)
                if let day = store.day {
                    Text(shortDate(day.date)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("itinerary-panel-heading")
            if !compact {
                Text(panelInfo).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }.contextMenu {
            if let day = store.day {
                Button("日期标题", systemImage: "pencil") { dayTitle = day.title ?? ""; editingDayTitle = true }
                Button("删除日期", systemImage: "trash", role: .destructive) { deletingPanelDay = true }
                    .disabled((store.trip?.days.count ?? 0) <= 1 || store.saving)
            } else if let trip = store.trip {
                Button("编辑旅行", systemImage: "pencil") { editingTrip = trip }
            }
        }
    }

    @ViewBuilder private var panelBackButton: some View {
        if let trip = store.trip {
            Button {
                showDates = false
                store.select(trip: store.day == nil ? nil : trip, focus: false)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .accessibilityLabel("上一层").accessibilityIdentifier("journey-back")
        }
    }

    private var panelSearch: some View {
        HStack(spacing: 8) {
            searchField
            Button { showSettings = true } label: {
                Image(systemName: "gearshape").font(.system(size: 19)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }.accessibilityLabel("连接设置")
        }.padding(.horizontal, 18).padding(.vertical, 10)
    }
    // One editing surface on iPad: navigation, search, dates, content and route settings.
    private func workspacePanel(topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                panelBackButton
                panelHeading()
                Spacer()
                Button { togglePanel() } label: {
                    Image(systemName: "sidebar.left").foregroundStyle(Theme.muted).frame(width: 40, height: 40)
                }.accessibilityLabel("收起行程").accessibilityIdentifier("itinerary-panel-toggle")
            }.padding(.horizontal, 18).padding(.top, 8)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
                    if value.translation.width < -50 && abs(value.translation.height) < abs(value.translation.width) * 0.5 {
                        togglePanel()
                    }
                })
            panelSearch
            Divider().opacity(0.55)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if store.searching || !store.searchResults.isEmpty {
                        Text("搜索结果").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                        if store.searching { ProgressView().frame(maxWidth: .infinity).padding(20) }
                        searchRows
                    } else {
                        itineraryContents
                    }
                }.padding(18)
            }.scrollDismissesKeyboard(.interactively)
            Divider().opacity(0.55)
            HStack(spacing: 8) {
                Text("MapAnNai").font(.system(size: 11, weight: .semibold, design: .rounded)).foregroundStyle(Theme.muted)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                else {
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
                        .accessibilityLabel("同步数据")
                }
            }.padding(.horizontal, 18).padding(.bottom, 8)
        }
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .padding(.leading, leftInset)
        .environment(\.colorScheme, .light).tint(Theme.cyan)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.muted)
            TextField("搜索地点", text: $store.searchText).font(.subheadline).submitLabel(.search)
                .onSubmit { Task { await store.search() } }.autocorrectionDisabled()
            if store.searching { ProgressView().controlSize(.small) }
            else if !store.searchText.isEmpty {
                Button { store.clearSearch() } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.muted) }.accessibilityLabel("清除搜索")
                Button("搜索") { Task { await store.search() } }.font(.caption.weight(.semibold))
            }
        }.padding(.horizontal, 12).frame(height: 44)
            .background(Theme.consoleRaised, in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(Theme.text).tint(Theme.cyan).environment(\.colorScheme, .light)
    }
    private var searchRows: some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(store.searchResults.enumerated()), id: \.element.id) { index, place in
                Button { store.choose(place) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(index + 1)").font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .frame(width: 24, height: 24).background(Color.red, in: Circle())
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                            Text(place.address).font(.caption).foregroundStyle(Theme.muted)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.vertical, 12).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("search-result-\(place.id)")
                Divider()
            }
        }
    }
    private var locationButton: some View {
        Button { location.request { store.locating = UUID() } } label: {
            Image(systemName: "location.viewfinder").font(.system(size: 20, weight: .medium)).foregroundStyle(Theme.cyan)
                .frame(width: 48, height: 48).background(.white, in: Circle())
                .overlay(Circle().stroke(Theme.cyan.opacity(0.15), lineWidth: 1).allowsHitTesting(false))
                .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
        }.accessibilityLabel("定位到当前位置")
    }
    private func togglePanel() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.23)) { expanded.toggle() }
    }

    private func phonePanel(layout: MapLayout, topInset: CGFloat, bottomInset: CGFloat) -> some View {
        let fullHeight = ItineraryDetent.full.height(in: layout.height) + topInset
        let baseHeight = sheetDetent == .full ? fullHeight : sheetDetent.height(in: layout.height)
        let height = max(ItineraryDetent.compact.height(in: layout.height), min(fullHeight, baseHeight - sheetDrag))
        let headerInset = max(0, min(topInset, height - layout.height))
        let compactHeader = height < 100
        return VStack(spacing: 0) {
            VStack(spacing: compactHeader ? 2 : 10) {
                Capsule().fill(Theme.muted.opacity(0.3)).frame(width: 36, height: 5)
                    .frame(height: compactHeader ? 10 : 14)
                HStack(spacing: 8) {
                    panelBackButton
                    Button {
                        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                            sheetDetent = sheetDetent == .compact ? .half : .compact
                        }
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            panelHeading(compact: compactHeader)
                                .frame(minHeight: 44, alignment: compactHeader ? .center : .topLeading)
                            Spacer(minLength: 4)
                            PanelChevron().stroke(Theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                                .frame(width: 12, height: 6)
                                .rotationEffect(.degrees(sheetDetent == .compact ? 180 : 0))
                                .frame(width: 44, height: compactHeader ? 44 : panelTitleLineHeight)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("旅途面板")
                        .accessibilityIdentifier("itinerary-panel-toggle")
                        .accessibilityAdjustableAction { direction in
                            if direction == .increment { sheetDetent = ItineraryDetent(rawValue: min(2, sheetDetent.rawValue+1)) ?? .full }
                            else { sheetDetent = ItineraryDetent(rawValue: max(0, sheetDetent.rawValue-1)) ?? .compact }
                        }
                }.padding(.horizontal, 18)
            }
            .padding(.top, headerInset).frame(height: min(76, height) + headerInset).contentShape(Rectangle())
            .highPriorityGesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
                .onChanged { value in
                    var transaction = Transaction(); transaction.disablesAnimations = true
                    withTransaction(transaction) { sheetDrag = value.translation.height }
                }
                .onEnded { value in
                    let target = baseHeight - value.translation.height - (value.predictedEndTranslation.height - value.translation.height) * 0.35
                    let next = ItineraryDetent.allCases.min {
                        abs(($0 == .full ? fullHeight : $0.height(in: layout.height)) - target) <
                        abs(($1 == .full ? fullHeight : $1.height(in: layout.height)) - target)
                    } ?? sheetDetent
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.9)) {
                        sheetDrag = 0; sheetDetent = next
                    }
                })
            if height > 120 {
                Divider().overlay(Theme.cyan.opacity(0.2))
                panelSearch
                ScrollView {
                    if store.searching || !store.searchResults.isEmpty {
                        searchRows.padding(.horizontal, 18)
                    } else {
                        itineraryContents.padding(.horizontal, 18).padding(.vertical, 14)
                    }
                }.scrollDismissesKeyboard(.interactively).frame(maxHeight: .infinity)
                .accessibilityIdentifier("itinerary-marker-list")
                }
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .background(Theme.console, in: UnevenRoundedRectangle(topLeadingRadius: sheetDetent == .full ? 0 : 20, topTrailingRadius: sheetDetent == .full ? 0 : 20))

        .shadow(color: Theme.ink.opacity(0.09), radius: 12, y: -3)
        .environment(\.colorScheme, .light).tint(Theme.cyan)
        .accessibilityElement(children: .contain).accessibilityIdentifier("phone-itinerary-panel")
    }
    @ViewBuilder private var itineraryContents: some View {
        if store.loading && store.markers.isEmpty { ProgressView("同步地点与旅行…").frame(maxWidth: .infinity).padding(24) }
        else if !settings.configured && !store.demo {
            EmptyView()
        } else if let day = store.day {
            DayContentsView(store: store, day: day)
        } else if let trip = store.trip {
            JourneyDaysContents(store: store, trip: trip)
        } else {
            JourneyOverviewContents(store: store)
        }
    }


}

@MainActor final class LocationPermission: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var onAllowed: (() -> Void)?
    override init() { super.init(); manager.delegate = self }
    func request(_ action: @escaping () -> Void) {
        onAllowed = action
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { action(); onAllowed = nil }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { onAllowed?(); onAllowed = nil }
    }
}
