import SwiftUI
import CoreLocation

struct HomeView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    // Only presentation changes invalidate Home/map; streaming tokens are observed inside the chat view.
    @State private var aiPlanner = AIPlannerStore()
    @State private var aiPresented = false
    @State private var aiReturnDetent: ItineraryDetent?
    @State private var showSettings = false
    @State private var creatingTrip = false
    @State private var showDates = false
    @State private var editingTrip: Trip?
    @State private var editingDayTitle = false
    @State private var dayTitle = ""
    @State private var deletingPanelDay = false
    @State private var expanded = true
    @State private var journeyAvailableHeight: CGFloat = 0
    @State private var nativeJourneyPresented = false
    @State private var journeyPath: [JourneyDestination] = []
    @State private var journeyNavigationWidth: CGFloat = 0
    @State private var sheetDetent: ItineraryDetent = .half
    @State private var sheetDrag: CGFloat = 0
    @State private var routeReturnDetent: ItineraryDetent?
    @State private var searchReturnDetent: ItineraryDetent?
    @State private var searchReturnExpanded = true
    @StateObject private var location = LocationPermission()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let sidebar = horizontalSizeClass == .regular && geometry.size.width >= 700
            Group {
                if sidebar { modalContent(mapPage) }
                else { mapPage }
            }
                .sheet(isPresented: Binding(get: { !sidebar && nativeJourneyPresented }, set: { nativeJourneyPresented = $0; if !$0 && aiPresented { aiPlanner.close() } }), onDismiss: { nativeJourneyPresented = true }) {
                    modalContent(panelWorkspace(sidebar: false))
                        .presentationDetents(!aiPresented ? [.height(compactJourneyHeight), .medium, .large] : [.medium, .large], selection: nativeJourneyDetent)
                        .presentationDragIndicator(aiPresented && UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible)
                        .presentationBackground { JourneySheetBackground(availableHeight: journeyAvailableHeight) }
                        .presentationBackgroundInteraction(.enabled)
                        .presentationContentInteraction(.resizes)
                        .interactiveDismissDisabled(!aiPresented)
                }
                .onAppear { nativeJourneyPresented = true }
                .task(id: settings.revision) {
                    await aiPlanner.configure(for: settings)
                    if ProcessInfo.processInfo.arguments.contains("--ai-planner-demo") { aiPlanner.presented = true }
                }
                .onReceive(aiPlanner.$presented.removeDuplicates()) { open in
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        aiPresented = open
                        if !sidebar {
                            if open { aiReturnDetent = sheetDetent; sheetDetent = .half }
                            else if let original = aiReturnDetent { sheetDetent = original; aiReturnDetent = nil }
                        }
                    }
                }
                .onChange(of: sidebar) { _, _ in nativeJourneyPresented = true }
                .onDisappear { aiPlanner.close() }
        }
    }

    @ViewBuilder private func panelWorkspace(sidebar: Bool) -> some View {
        ZStack {
            if aiPresented && !sidebar {
                AIPlannerView(planner: aiPlanner, store: store, onOpenSettings: { showSettings = true })
            }
            journeyNavigation(sidebar: sidebar)
                .opacity(!store.placeSearchPresented && !aiPresented && (sidebar || !compactNavigationVisible) ? 1 : 0)
                .allowsHitTesting(!store.placeSearchPresented && !aiPresented && (sidebar || !compactNavigationVisible))
                .accessibilityHidden(store.placeSearchPresented || aiPresented || (!sidebar && compactNavigationVisible))
            if !sidebar && compactNavigationVisible {
                compactJourneyControls
            }
            if store.placeSearchPresented && !aiPresented {
                DayMarkerPicker(store: store, day: store.addPlaceDay, compact: !sidebar && sheetDetent == .compact,
                    onInput: { if !sidebar { sheetDetent = .full } },
                    onSearch: { if !sidebar { sheetDetent = .half } })
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.placeSearchPresented)
        .accessibilityElement(children: .contain)
            .accessibilityIdentifier(sidebar ? "sidebar-workspace" : "phone-itinerary-panel")
    }

    private var mapPage: some View {
        GeometryReader { proxy in
            let layout = MapLayout(width: proxy.size.width, height: proxy.size.height,
                                   regularWidth: horizontalSizeClass == .regular, expanded: expanded,
                                   sheetHeight: sheetDetent == .compact ? compactJourneyHeight : sheetDetent == .half ? proxy.size.height * 0.5 : sheetDetent.height(in: proxy.size.height))
            let cameraInsets = aiPresented && layout.usesSidebar
                ? MapViewportInsets(top: 50, left: 35, bottom: 70, right: min(420, proxy.size.width * 0.46) + 25)
                : layout.insets
            mapContent(layout: layout, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom, leftInset: proxy.safeAreaInsets.leading)
                .onAppear {
                    store.mapViewportInsets = cameraInsets
                    journeyAvailableHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                }
                .onChange(of: proxy.size) { _, size in
                    journeyAvailableHeight = size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                }
                .onChange(of: cameraInsets) { _, insets in store.mapViewportInsets = insets }
                .onChange(of: store.routeSelectionRequest) { _, _ in
                    showDates = false; expanded = true
                    if !layout.usesSidebar {
                        if routeReturnDetent == nil { routeReturnDetent = sheetDetent }
                        sheetDrag = 0
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { sheetDetent = .half }
                    }
                }
                .onChange(of: store.selectedMarker?.id) { _, markerID in
                    guard markerID != nil else { return }
                    showDates = false
                    // Details preserve the journey detent, including after dismissal.
                }
        }
    }

    private func modalContent<Content: View>(_ content: Content) -> some View {
        content
        .sheet(isPresented: $creatingTrip) { TripEditorView(store: store, trip: nil).presentationDragIndicator(.visible) }
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
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, store: store, aiPlanner: aiPlanner).presentationDragIndicator(.visible) }
        .sheet(item: Binding(get: { !store.placeSearchPresented ? store.selectedMarker : nil }, set: { store.selectedMarker = $0 })) { marker in MarkerDetailView(store: store, marker: marker, onNavigateItinerary: {
                expanded = true
                if sheetDetent == .compact { sheetDetent = .half }
            }) }
        .sheet(item: Binding(get: { !store.placeSearchPresented ? store.draft : nil }, set: { store.draft = $0 })) { draft in
            if UIDevice.current.userInterfaceIdiom == .pad {
                MarkerEditorView(store: store, initial: draft).id(draft.id)
                    .onAppear { store.draftExpanded = true }
            } else {
                MarkerEditorView(store: store, initial: draft).id(draft.id)
                    .presentationDetents([.medium, .large], selection: Binding(
                        get: { store.draftExpanded ? .large : .medium },
                        set: { store.draftExpanded = $0 == .large }))
                    .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: store.placeSearchPresented) { _, open in
            sheetDrag = 0; showDates = false
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.28)) {
                if open {
                    searchReturnDetent = sheetDetent
                    searchReturnExpanded = expanded
                    sheetDetent = .half; expanded = true
                } else {
                    sheetDetent = searchReturnDetent ?? .half
                    expanded = searchReturnExpanded
                    searchReturnDetent = nil
                }
            }
        }
        .onChange(of: store.draft?.id) { old, new in
            guard !store.placeSearchPresented else { return }
            if new != nil, UIDevice.current.userInterfaceIdiom != .pad, store.selectedSearchPlaceID != nil { sheetDetent = .compact }
            else if old != nil, new == nil, !store.searchResults.isEmpty, !store.placeSearchPresented { sheetDetent = .half }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: settings.planning) { _, _ in store.rebuildRoutes() }
        .onChange(of: settings.mode) { _, _ in store.rebuildRoutes() }
    }

    private var compactJourneyHeight: CGFloat { store.trip == nil ? 68 : 80 }
    private var compactNavigationVisible: Bool {
        sheetDetent == .compact && !store.placeSearchPresented && !aiPresented
    }

    private var nativeJourneyDetent: Binding<PresentationDetent> {
        Binding(get: {
            switch sheetDetent {
            case .compact: .height(compactJourneyHeight)
            case .half: .medium
            case .full: .large
            }
        }, set: { value in
            sheetDetent = value == .large ? .full : value == .medium ? .half : .compact
        })
    }

    private var nativeJourneyPanel: some View {
        journeyNavigation(sidebar: false)
            .accessibilityElement(children: .contain).accessibilityIdentifier("phone-itinerary-panel")
    }

    private var journeyDestinations: [JourneyDestination] {
        guard let trip = store.trip else { return [] }
        var path: [JourneyDestination] = [.trip(trip.id)]
        if let day = store.day { path.append(.day(trip.id, day.id)) }
        return path
    }
    private func journeyNavigation(sidebar: Bool) -> some View {
        NavigationStack(path: $journeyPath) {
            journeyPage(nil, sidebar: sidebar)
                .navigationDestination(for: JourneyDestination.self) { destination in
                    journeyPage(destination, sidebar: sidebar)
                }
        }.tint(Theme.accent)
            .background {
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { journeyNavigationWidth = geometry.size.width }
                        .onChange(of: geometry.size.width) { _, width in journeyNavigationWidth = width }
                }
            }
            .onAppear {
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { journeyPath = journeyDestinations }
            }
            .onChange(of: journeyDestinations) { _, path in
                guard journeyPath != path else { return }
                withAnimation(reduceMotion ? nil : .default) { journeyPath = path }
            }
            .onChange(of: journeyPath) { previousPath, path in
                if path.count < previousPath.count, let original = routeReturnDetent {
                    routeReturnDetent = nil
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) { sheetDetent = original }
                }
                guard path != journeyDestinations else { return }
                switch path.last {
                case let .trip(id): store.select(trip: store.trips.first { $0.id == id }, focus: path.count > previousPath.count)
                case let .day(tripID, dayID):
                    if let trip = store.trips.first(where: { $0.id == tripID }) {
                        store.select(trip: trip, day: trip.days.first { $0.id == dayID }, focus: path.count > previousPath.count)
                    }
                case nil: store.select(trip: nil, focus: false)
                }
            }
    }
    private func scope(_ destination: JourneyDestination?) -> (trip: Trip?, day: TripDay?) {
        switch destination {
        case let .trip(id): (store.trips.first { $0.id == id }, nil)
        case let .day(tripID, dayID):
            if let trip = store.trips.first(where: { $0.id == tripID }) {
                (trip, trip.days.first { $0.id == dayID })
            } else { (nil, nil) }
        case nil: (nil, nil)
        }
    }
    private func journeyTitle(_ destination: JourneyDestination?) -> String {
        let page = scope(destination)
        if let trip = page.trip, let day = page.day {
            return "第\((trip.days.sorted { $0.date < $1.date }.firstIndex { $0.id == day.id } ?? 0) + 1)天"
        }
        return page.trip?.name ?? "我的旅途"
    }
    private func journeyHeading(_ destination: JourneyDestination?, sidebar: Bool) -> some View {
        let page = scope(destination)
        return VStack(alignment: .center, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(!sidebar && sheetDetent == .compact ? (page.trip?.name ?? "我的旅途") : journeyTitle(destination)).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("itinerary-panel-title")
                if let day = page.day, sidebar || sheetDetent != .compact { Text(shortDate(day.date)).font(.caption).foregroundStyle(.secondary) }
            }
            if sheetDetent != .compact {
                if let day = page.day {
                    Text([day.title, "\(day.markerIds.count)个地点"].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else if let trip = page.trip {
                    Text("\(shortDate(trip.startDate)) – \(shortDate(trip.endDate)) · \(trip.days.count)天")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                } else { Text("\(store.trips.count)个旅行").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .frame(width: max(80, journeyNavigationWidth - 2 * (sidebar ? 84 : 116)))
        .multilineTextAlignment(.center)
        .contextMenu {
            if let day = page.day {
                Button("日期标题", systemImage: "pencil") { dayTitle = day.title ?? ""; editingDayTitle = true }
                DestructiveMenuButton(title: "删除日期", systemImage: "trash") { deletingPanelDay = true }
                    .disabled((page.trip?.days.count ?? 0) <= 1 || store.saving)
            } else if let trip = page.trip {
                Button("编辑旅行", systemImage: "pencil") { editingTrip = trip }
            }
        }
    }
    @ViewBuilder private func journeyPage(_ destination: JourneyDestination?, sidebar: Bool) -> some View {
        let page = scope(destination)
        Group {
            if !store.placeSearchPresented && (store.searching || !store.searchResults.isEmpty) {
                List {
                    Section { panelSearch }
                    if store.searching { ProgressView().frame(maxWidth: .infinity) }
                    searchRows
                }
            } else if let day = page.day {
                DayContentsView(store: store, day: day, searchContent: { EmptyView() }, onViewRoute: {
                    if !sidebar {
                        withAnimation(reduceMotion ? nil : .default) { sheetDrag = 0; sheetDetent = .half }
                    }
                })
            } else if let trip = page.trip {
                JourneyDaysContents(store: store, searchContent: { EmptyView() }, trip: trip, usesNativeNavigation: true)
            } else {
                JourneyOverviewContents(store: store, searchContent: { EmptyView() }, settingsContent: { journeySettingsRow }, usesNativeNavigation: true)
            }
        }.listStyle(.insetGrouped).buttonStyle(.automatic)
            .opacity(!sidebar && sheetDetent == .compact ? 0 : 1)
            .allowsHitTesting(sidebar || sheetDetent != .compact)
            .scrollContentBackground(sidebar ? .visible : .hidden)
            .contentMargins(.top, 0, for: .scrollContent).listSectionSpacing(8)
            .id(ItineraryScrollIdentity(tripID: page.trip?.id, dayID: page.day?.id,
                                        showingSearch: store.searching || !store.searchResults.isEmpty))
            .scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("itinerary-marker-list")
            .modifier(JourneyNavigationBackground())
            .navigationTitle(journeyTitle(destination)).navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden()
            .toolbar { journeyToolbar(sidebar: sidebar, destination: destination) }
            .background(JourneyToolbarContainerOffset())

    }

    @ToolbarContentBuilder private func journeyToolbar(sidebar: Bool, destination: JourneyDestination?) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            journeyHeading(destination, sidebar: sidebar).offset(y: !sidebar && sheetDetent == .compact ? 2 : 4)
                .accessibilityAction(named: "展开旅途") { if !sidebar { sheetDetent = .full } }
                .accessibilityAction(named: "收起旅途") { if !sidebar { sheetDetent = .compact } }
        }
        journeyLeadingControl(destination: destination, sidebar: sidebar)
        if !sidebar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { location.request { store.locating = UUID() } } label: {
                    toolbarActionIcon("location")
                }.accessibilityLabel("定位到当前位置").accessibilityIdentifier("itinerary-header-location")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                if sidebar { togglePanel() }
                else { store.beginAddingPlace(to: scope(destination).day) }
            } label: {
                toolbarActionIcon(sidebar ? "sidebar.left" : "magnifyingglass")
            }.accessibilityLabel(sidebar ? "收起行程" : "搜索地点")
                .accessibilityIdentifier(sidebar ? "itinerary-panel-toggle" : "itinerary-search")
        }
    }

    @ToolbarContentBuilder private func journeyLeadingControl(destination: JourneyDestination?, sidebar: Bool) -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            journeyLeadingItem(destination: destination, sidebar: sidebar).sharedBackgroundVisibility(.hidden)
        } else {
            journeyLeadingItem(destination: destination, sidebar: sidebar)
        }
    }
    private func journeyLeadingItem(destination: JourneyDestination?, sidebar: Bool) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 0) {
                if scope(destination).trip != nil {
                    Button {
                        guard !journeyPath.isEmpty else { return }
                        withAnimation(reduceMotion ? nil : .default) { journeyPath.removeLast() }
                    } label: {
                        toolbarActionIcon("chevron.left").frame(width: 30, height: 30)
                    }
                        .modifier(JourneyCircleButtonStyle())
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                        .accessibilityLabel("上一层").accessibilityIdentifier("journey-back")
                } else {
                    overviewToggleButton(sidebar: sidebar)

                }
            }
            // Match the native trailing toolbar reservation so principal stays at the bar center.
            .frame(width: sidebar ? 44 : 88, alignment: .leading)
        }
    }
    private func overviewToggleButton(sidebar: Bool) -> some View {
        let isCollapsed = !sidebar && sheetDetent == .compact
        return Button {
            if isCollapsed { creatingTrip = true }
            else {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    if sidebar { expanded = false } else { sheetDetent = .compact }
                }
            }
        } label: {
            toolbarActionIcon("plus")
                .rotationEffect(.degrees(isCollapsed ? 0 : 45))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: isCollapsed)
                .frame(width: 30, height: 30)
        }.modifier(JourneyCircleButtonStyle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .accessibilityLabel(isCollapsed ? "添加旅途" : "收起旅途")
            .accessibilityIdentifier(isCollapsed ? "compact-create-journey" : "close-journey")
    }

    private func mapContent(layout: MapLayout, topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MapSurface(store: store, settings: settings, onOpenSettings: { showSettings = true })
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .ignoresSafeArea()
            if aiPresented && layout.usesSidebar {
                AIPlannerView(planner: aiPlanner, store: store, onOpenSettings: { showSettings = true })
                    .padding(.top, 60)
                    .frame(width: min(420, layout.width * 0.46), height: layout.height)
                    .background(.regularMaterial)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(2)
            }
            if AIPlannerStore.entryEnabled && (!aiPresented || layout.usesSidebar) {
                Button { if aiPresented { aiPlanner.close() } else { aiPlanner.presented = true } } label: {
                    Image(systemName: "bubble.left").font(.system(size: 20, weight: .regular)).foregroundStyle(.primary).frame(width: 32, height: 32)
                }.modifier(AIEntryButtonStyle()).accessibilityLabel(aiPresented ? "收起AI助手" : "AI 助手")
                    .zIndex(3)
                    .accessibilityIdentifier("open-ai-planner")
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16).padding(.top, 8)
            }
            if layout.usesSidebar {
                HStack(spacing: 0) {
                    if expanded {
                        workspacePanel(topInset: topInset, bottomInset: bottomInset, leftInset: leftInset)
                            .frame(width: layout.sidebarWidth + leftInset, height: layout.height + topInset + bottomInset)
                            .background(.regularMaterial)
                            .overlay(alignment: .trailing) { Rectangle().fill(Theme.ink.opacity(0.08)).frame(width: 1) }
                            .accessibilityElement(children: .contain).accessibilityIdentifier("landscape-itinerary-sidebar")
                            .offset(x: -leftInset, y: -topInset)
                    } else {
                        Button { togglePanel() } label: {
                            Image(systemName: "sidebar.left")
                                .font(.system(size: 20)).frame(width: 48, height: 48)
                                .softSurface(fill: Theme.console)
                        }.accessibilityLabel("展开行程").padding(.leading, 16).padding(.top, 8).frame(maxHeight: .infinity, alignment: .top)
                    }
                    Spacer(minLength: 0)
                }.frame(width: layout.width, height: layout.height, alignment: .topLeading)
                    .opacity(aiPresented ? 0 : 1)
                    .allowsHitTesting(!aiPresented)
                    .accessibilityHidden(aiPresented)
                locationButton.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 20).padding(.bottom, 20)
            }
            let capsulesVisible = layout.usesSidebar && !store.placeSearchPresented && !aiPresented
            ZStack {
                if capsulesVisible {
                    navigationCapsules.transition(.opacity)
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .center)
            .opacity(capsulesVisible ? 1 : 0)
            .allowsHitTesting(capsulesVisible)
            .accessibilityHidden(!capsulesVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: capsulesVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: store.tripID != nil)

        }
        .onChange(of: store.tripID) { _, _ in showDates = false }
    }

    private var compactJourneyControls: some View {
        HStack(spacing: 4) {
            Group {
            if store.trip != nil {
            Button {
                guard !journeyPath.isEmpty else { return }
                withAnimation(reduceMotion ? nil : .default) { journeyPath.removeLast() }
            } label: {
                toolbarActionIcon("chevron.left").frame(width: 30, height: 30)
            }.modifier(JourneyCircleButtonStyle())
                .frame(width: 44, height: 44)
                .accessibilityLabel("上一层").accessibilityIdentifier("journey-back")
            } else {
                overviewToggleButton(sidebar: false)
            }
            }.frame(width: 88, alignment: .leading)
            VStack(spacing: 0) {
                compactDateNavigation
                Text(store.trip?.name ?? "我的旅途")
                    .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("itinerary-panel-title")
            }.frame(maxWidth: .infinity)
            HStack(spacing: 0) {
                Button { location.request { store.locating = UUID() } } label: {
                    toolbarActionIcon("location").frame(width: 44, height: 44)
                }.accessibilityLabel("定位到当前位置").accessibilityIdentifier("itinerary-header-location")
                Button { store.beginAddingPlace(to: store.day) } label: {
                    toolbarActionIcon("magnifyingglass").frame(width: 44, height: 44)
                }.accessibilityLabel("搜索地点").accessibilityIdentifier("itinerary-search")
            }.buttonStyle(.plain).foregroundStyle(Theme.accent)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("compact-journey-controls")
    }

    @ViewBuilder private var compactDateNavigation: some View {
        if let trip = store.trip {
            Menu {
                ForEach(trip.days.sorted { $0.date < $1.date }) { day in
                    Button { store.select(trip: trip, day: day) } label: {
                        if store.dayID == day.id {
                            Label("第\(dayNumber(day))天 · \(shortDate(day.date))", systemImage: "checkmark")
                        } else {
                            Text("第\(dayNumber(day))天 · \(shortDate(day.date))")
                        }
                    }.accessibilityIdentifier("date-option-\(day.id)")
                }
            } label: {
                HStack(spacing: 8) {
                    Text(store.day.map { "第\(dayNumber($0))天" } ?? "选择日期")
                        .font(.subheadline.weight(.semibold))
                    if let day = store.day {
                        Text(shortDate(day.date)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                }.frame(maxWidth: .infinity).frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).tint(Theme.accent)
                .accessibilityLabel("选择日期").accessibilityIdentifier("date-selector")
        }
    }

    @ViewBuilder private var navigationCapsules: some View {
        if let trip = store.trip {
            HStack(spacing: 8) {
                Button { showDates = false; store.select(trip: trip, focus: false) } label: {
                    Text(trip.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 14).frame(height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).foregroundStyle(Theme.text).accessibilityIdentifier("trip-breadcrumb")
                Text("›").foregroundStyle(Theme.muted)
                Menu {
                    ForEach(trip.days.sorted { $0.date < $1.date }) { day in
                        Button {
                            store.select(trip: trip, day: day)
                        } label: {
                            if store.dayID == day.id {
                                Label("第\(dayNumber(day))天 · \(shortDate(day.date))", systemImage: "checkmark")
                            } else {
                                Text("第\(dayNumber(day))天 · \(shortDate(day.date))")
                            }
                        }.accessibilityIdentifier("date-option-\(day.id)")
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(store.day.map { "第\(dayNumber($0))天" } ?? "总览 · 共\(trip.days.count)天")
                            .font(.subheadline.weight(.medium)).lineLimit(1)
                        if let day = store.day {
                            Text(shortDate(day.date)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
                    }.frame(height: 44)
                }.foregroundStyle(.tint).accessibilityIdentifier("date-selector").accessibilityLabel("选择日期")
                Button { showDates = false; store.select(trip: nil, focus: false) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.muted)
                        .frame(width: 30, height: 30)
                        .frame(width: 36, height: 44)
                }.accessibilityLabel("退出旅行").accessibilityIdentifier("exit-journey")
            }.padding(.horizontal, 6).modifier(NativeNavigationSurface())
                .background {
                    Color.clear.accessibilityElement().accessibilityLabel("旅行导航区域")
                        .accessibilityIdentifier("journey-navigation-bounds")
                }
                .accessibilityElement(children: .contain).accessibilityIdentifier("journey-navigation")
        }
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
        return store.trip?.name ?? "我的旅途"
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
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: panelTitle)
                    .accessibilityIdentifier("itinerary-panel-title")
                if let day = store.day {
                    Text(shortDate(day.date)).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }.alignmentGuide(.panelTitleCenter) { $0[VerticalAlignment.center] }
                .accessibilityElement(children: .contain).accessibilityIdentifier("itinerary-panel-heading")
            if !compact {
                Text(panelInfo).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
            }
        }.contextMenu {
            if let day = store.day {
                Button("日期标题", systemImage: "pencil") { dayTitle = day.title ?? ""; editingDayTitle = true }
                DestructiveMenuButton(title: "删除日期", systemImage: "trash") { deletingPanelDay = true }
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

    private var journeySettingsRow: some View {
        Button { showSettings = true } label: {
            Label("设置", systemImage: "gearshape")
                .fullRowActionLabel()
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityIdentifier("itinerary-settings-bottom")
    }
    private var panelSearch: some View {
        searchField
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
    private var panelActionTransition: AnyTransition {
        reduceMotion ? .identity : .opacity.combined(with: .scale(scale: 0.85))
    }
    // Native toolbars provide their own padding and touch targets.
    private func toolbarActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .resizable().scaledToFit()
            .font(.system(size: 20, weight: .regular))
            .frame(width: 20, height: 20, alignment: .center)
    }

    // Normalize the drawn symbol bounds, not just the font size or tap target.
    private func panelActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .resizable().scaledToFit()
            .font(.system(size: 20, weight: .regular))
            .frame(width: 20, height: 20)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }
    private var addTripButton: some View {
        Button { creatingTrip = true } label: {
            panelActionIcon("plus")
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityLabel("创建旅行").accessibilityIdentifier("create-journey")
    }
    private var settingsButton: some View {
        Button { showSettings = true } label: {
            panelActionIcon("gearshape")
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityLabel("连接设置").accessibilityIdentifier("itinerary-header-settings")
    }
    // One editing surface on iPad: navigation, search, dates, content and route settings.
    private func workspacePanel(topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        panelWorkspace(sidebar: true)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .padding(.leading, leftInset)
        .environment(\.colorScheme, .light).tint(Theme.cyan)
    }

    // Give each navigation scope its own scroll container. Data refreshes within the
    // same scope retain position, while a new trip/day starts at its first row.
    private var itineraryScrollIdentity: ItineraryScrollIdentity {
        ItineraryScrollIdentity(tripID: store.tripID, dayID: store.dayID,
                                showingSearch: store.searching || !store.searchResults.isEmpty)
    }

    private var searchField: some View {
        NativePlaceSearchBar(text: $store.searchText, searching: store.searching,
                             onSearch: { Task { await store.search() } }, onClear: { store.clearSearch() })
            .frame(height: 56)
    }
    private var animatedItineraryList: some View {
        ZStack {
            itineraryList.id(itineraryScrollIdentity)
                .transition(.opacity.combined(with: .offset(x: 18)))
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: itineraryScrollIdentity)
    }
    private var itineraryList: some View {
        Group {
            if !store.placeSearchPresented && (store.searching || !store.searchResults.isEmpty) {
                List {
                    Section { panelSearch }
                    if store.searching { ProgressView().frame(maxWidth: .infinity) }
                    searchRows
                }
            } else {
                itineraryContents
            }
        }.listStyle(.insetGrouped).buttonStyle(.borderless).scrollContentBackground(.visible)
            .contentMargins(.top, 0, for: .scrollContent)
            .listSectionSpacing(8)
            .id(itineraryScrollIdentity).scrollDismissesKeyboard(.interactively)
            .accessibilityIdentifier("itinerary-marker-list")
    }
    private var searchRows: some View {
        Group {
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
            SearchPaginationFooter(store: store)
        }
    }
    private var locationButton: some View {
        Button { location.request { store.locating = UUID() } } label: {
            Image(systemName: "location").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.cyan)
                .frame(width: 48, height: 48).background(.white, in: Circle())
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
        let showHeaderActions = store.trip == nil && sheetDetent != .compact
        return VStack(spacing: 0) {
            VStack(spacing: compactHeader ? 2 : 10) {
                Capsule().fill(Theme.muted.opacity(0.3)).frame(width: 36, height: 5)
                    .frame(height: compactHeader ? 10 : 14)
                HStack(alignment: .panelTitleCenter, spacing: 4) {
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
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("旅途面板")
                        .accessibilityIdentifier("itinerary-panel-toggle")
                        .accessibilityAdjustableAction { direction in
                            if direction == .increment { sheetDetent = ItineraryDetent(rawValue: min(2, sheetDetent.rawValue+1)) ?? .full }
                            else { sheetDetent = ItineraryDetent(rawValue: max(0, sheetDetent.rawValue-1)) ?? .compact }
                        }
                    HStack(spacing: 0) {
                        if showHeaderActions {
                            addTripButton.transition(panelActionTransition)
                        }
                        if UIDevice.current.userInterfaceIdiom == .phone {
                            Button { location.request { store.locating = UUID() } } label: {
                                panelActionIcon("location").foregroundStyle(Theme.accent)
                            }.buttonStyle(.plain).accessibilityLabel("定位到当前位置")
                                .accessibilityIdentifier("itinerary-header-location")
                        }
                        if showHeaderActions {
                            settingsButton.transition(panelActionTransition)
                        }
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                                sheetDetent = sheetDetent == .compact ? .half : .compact
                            }
                        } label: {
                            panelActionIcon("chevron.down").foregroundStyle(Theme.accent)
                                .rotationEffect(.degrees(sheetDetent == .compact ? 180 : 0))
                        }.buttonStyle(.plain)
                            .accessibilityLabel(sheetDetent == .compact ? "展开旅途" : "收起旅途")
                            .accessibilityIdentifier("itinerary-collapse")
                    }
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showHeaderActions)
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
                Divider()
                itineraryList.frame(maxHeight: .infinity)
                }
            Spacer(minLength: 0)
        }
        .frame(height: height)
        .padding(.bottom, bottomInset)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: sheetDetent == .full ? 0 : 20, topTrailingRadius: sheetDetent == .full ? 0 : 20))

        .shadow(color: Theme.ink.opacity(0.09), radius: 12, y: -3)
        .environment(\.colorScheme, .light).tint(Theme.cyan)
        .accessibilityElement(children: .contain).accessibilityIdentifier("phone-itinerary-panel")
    }
    @ViewBuilder private var itineraryContents: some View {
        if store.loading && store.markers.isEmpty { ProgressView("同步地点与旅行…").frame(maxWidth: .infinity).padding(24) }
        else if !settings.configured && !store.demo {
            EmptyView()
        } else if let day = store.day {
            DayContentsView(store: store, day: day, searchContent: { EmptyView() }, onViewRoute: {
                withAnimation(reduceMotion ? nil : .default) { sheetDrag = 0; sheetDetent = .half }
            })
        } else if let trip = store.trip {
            JourneyDaysContents(store: store, searchContent: { EmptyView() }, trip: trip)
        } else {
            JourneyOverviewContents(store: store, searchContent: { EmptyView() }, settingsContent: { journeySettingsRow })
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

private struct ItineraryScrollIdentity: Hashable {
    let tripID: String?
    let dayID: String?
    let showingSearch: Bool
}

private extension VerticalAlignment {
    private enum PanelTitleCenter: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
    }
    static let panelTitleCenter = VerticalAlignment(PanelTitleCenter.self)
}

enum JourneyDestination: Hashable {
    case trip(String)
    case day(String, String)
}

private struct AIEntryButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(.glass).buttonBorderShape(.circle).tint(.primary)
        } else {
            content.buttonStyle(.plain).padding(6).background(.regularMaterial, in: Circle())
        }
    }
}
