import SwiftUI
import CoreLocation

struct HomeView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    // Only presentation changes invalidate Home/map; streaming tokens are observed inside the chat view.
    @State private var aiPlanner = AIPlannerStore()
    @State private var aiPresented = false
    @State private var aiSheetDetent: PresentationDetent = .medium
    @State private var aiSettingsPresented = false
    @State private var showSettings = false
    @State private var noteComposerPreview = false
    @State private var creatingTrip = false
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
    @State private var routeReturnDetent: ItineraryDetent?
    @State private var markerReturnDetent: ItineraryDetent?
    @State private var mapDraftReady = true
    @State private var mapEditorActive = false
    @State private var markerReturnExpanded = true
    @State private var searchReturnDetent: ItineraryDetent?
    @State private var searchReturnExpanded = true
    @StateObject private var location = LocationPermission()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            let sidebar = horizontalSizeClass == .regular && geometry.size.width >= 700
            Group {
                if sidebar { modalContent(mapPage, sidebar: true) }
                else { mapPage }
            }
                .sheet(isPresented: Binding(get: { !sidebar && nativeJourneyPresented }, set: { nativeJourneyPresented = $0 }), onDismiss: { nativeJourneyPresented = true }) {
                    modalContent(panelWorkspace(sidebar: false))
                        .presentationDetents([.height(compactJourneyHeight), .medium, .large], selection: nativeJourneyDetent)
                        .presentationDragIndicator(.visible)
                        .presentationBackground { JourneySheetBackground(availableHeight: journeyAvailableHeight) }
                        .presentationBackgroundInteraction(.enabled)
                        .presentationContentInteraction(.resizes)
                        .interactiveDismissDisabled()
                }
                .onAppear { nativeJourneyPresented = true }
                .task(id: settings.revision) {
                    await aiPlanner.configure(for: settings)
                    #if DEBUG
                    if store.demo && ProcessInfo.processInfo.arguments.contains("--note-composer-preview") { noteComposerPreview = true }
                    if store.demo && ProcessInfo.processInfo.arguments.contains("--ai-chat-preview") {
                        aiPlanner.configuration = AIConfiguration(model: "preview")
                        let messages = (1...16).flatMap { index in
                            [AIMessage(role: "user", content: "第\(index)个问题：这一天怎么安排？"),
                             AIMessage(role: "assistant", content: index == 16 ? "最新回复：当天行程已整理好。" : "建议先游览附近的地点，再沿路线前往下一站，留出休息时间。")]
                        }
                        let conversation = AIConversation(title: "行程规划", messages: messages)
                        aiPlanner.conversations = [conversation]; aiPlanner.activeID = conversation.id
                    }
                    #endif
                    if ProcessInfo.processInfo.arguments.contains("--ai-planner-demo") { aiPlanner.presented = true }
                }
                .onReceive(aiPlanner.$presented.removeDuplicates()) { open in
                    withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) {
                        aiPresented = open
                        if open { aiSheetDetent = .medium }
                    }
                }
                .onChange(of: store.selectedMarker?.id) { _, id in
                    guard !sidebar, !store.placeSearchPresented else { return }
                    guard id != nil else {
                        restoreJourneyAfterMarker()
                        return
                    }
                    if markerReturnDetent == nil {
                        markerReturnDetent = sheetDetent
                        markerReturnExpanded = expanded
                    }
                    setJourneyDetent(.compact)
                }
                .onChange(of: sidebar) { _, _ in nativeJourneyPresented = true }
                .onDisappear { aiPlanner.close() }
        }
    }

    private func panelWorkspace(sidebar: Bool) -> some View {
        NativeSheetHeightReader(enabled: !sidebar) { geometry in
            let progress = sidebar ? 1 : JourneyPresentation.expandedProgress(
                height: geometry.visibleHeight, compactHeight: compactJourneyHeight)
            let journeyVisible = !store.placeSearchPresented
            let headerProgress = reduceMotion ? (compactNavigationVisible ? 0.0 : 1.0) : progress
            ZStack(alignment: .top) {
                journeyNavigation(sidebar: sidebar)
                    // Retain list space while UIKit is settling toward smaller model bounds.
                    .frame(height: sidebar ? nil : max(geometry.layoutHeight, geometry.visibleHeight), alignment: .top)
                    .animation(nil, value: store.placeSearchPresented)
                    .animation(nil, value: aiPresented)
                    .mask(alignment: .top) {
                        JourneyContentReveal(headerProgress: sidebar ? 1 : headerProgress,
                            headerHeight: compactJourneyHeight)
                            // Cover the native sheet bottom safe area as well as its content.
                            .ignoresSafeArea(.container, edges: .bottom)
                    }
                    .animation(AppMotion.crossfade(reduceMotion: reduceMotion)) { content in
                        content.opacity(journeyVisible ? 1 : 0)
                    }
                    .allowsHitTesting(journeyVisible && (sidebar || !compactNavigationVisible))
                    .accessibilityHidden(!journeyVisible || (!sidebar && compactNavigationVisible))
                if !sidebar && journeyVisible && (progress < 1 || compactNavigationVisible) {
                    compactJourneyControls
                        // The exiting header keeps its original center as the sheet grows.
                        .frame(height: min(geometry.visibleHeight, compactJourneyHeight))
                        .opacity(1 - headerProgress)
                        .animation(AppMotion.crossfade(reduceMotion: reduceMotion)) { content in
                            content.opacity(journeyVisible ? 1 : 0)
                        }
                        .allowsHitTesting(journeyVisible && compactNavigationVisible)
                        .accessibilityHidden(!journeyVisible || !compactNavigationVisible)
                        .transition(.identity)
                }
                if store.placeSearchPresented && !aiPresented {
                    DayMarkerPicker(store: store, day: store.addPlaceDay, compact: !sidebar && sheetDetent == .compact,
                        onInput: { if !sidebar { setJourneyDetent(.full) } },
                        onSearch: { if !sidebar { setJourneyDetent(.half) } })
                        .transition(AppMotion.workspaceTransition(edge: .bottom, reduceMotion: reduceMotion))
                        .zIndex(1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(AppMotion.presentation(reduceMotion: reduceMotion), value: store.placeSearchPresented)
            .animation(AppMotion.presentation(reduceMotion: reduceMotion), value: aiPresented)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(sidebar ? "sidebar-workspace" : "phone-itinerary-panel")
    }

    private func setJourneyDetent(_ detent: ItineraryDetent) {
        withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) { sheetDetent = detent }
    }

    private var mapPage: some View {
        GeometryReader { proxy in
            let layout = MapLayout(width: proxy.size.width, height: proxy.size.height,
                                   regularWidth: horizontalSizeClass == .regular, expanded: expanded,
                                   sheetHeight: sheetDetent == .compact ? compactJourneyHeight : sheetDetent == .half ? proxy.size.height * 0.5 : proxy.size.height)
            let cameraInsets = aiPresented && layout.usesSidebar
                ? MapViewportInsets(top: 50, left: 35, bottom: 70, right: min(420, Double(proxy.size.width) * 0.46) + 25)
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
                    expanded = true
                    if !layout.usesSidebar {
                        if routeReturnDetent == nil { routeReturnDetent = sheetDetent }
                        setJourneyDetent(.half)
                    }
                }
        }
    }

    private func modalContent<Content: View>(_ content: Content, sidebar: Bool = false) -> some View {
        content
        .fullScreenCover(isPresented: $noteComposerPreview) {
            NoteComposerPreview(placeName: "武康大楼", address: "上海市徐汇区淮海中路1850号")
        }
        .sheet(isPresented: $creatingTrip) { TripEditorView(store: store, trip: nil).presentationDragIndicator(.visible) }
        .sheet(item: $editingTrip) { TripEditorView(store: store, trip: $0).presentationDragIndicator(.visible) }
        .sheet(isPresented: $deletingPanelDay) {
            if let day = store.day { DayDeletionView(store: store, day: day) }
        }
        .alert("日期标题", isPresented: $editingDayTitle) {
            TextField("标题", text: $dayTitle)
            Button("取消", role: .cancel) {}
            Button("保存") { Task { if var day = store.day { day.title = dayTitle; _ = await store.updateDay(day) } } }
        }
        .sheet(isPresented: Binding(get: { aiPresented && !sidebar }, set: { if !$0 { aiPlanner.close() } })) {
            AIPlannerView(planner: aiPlanner, store: store, onOpenSettings: { aiSettingsPresented = true })
                .presentationDetents([.medium, .large], selection: $aiSheetDetent)
                .presentationDragIndicator(UIDevice.current.userInterfaceIdiom == .pad ? .hidden : .visible)
                .presentationBackgroundInteraction(.enabled)
                .sheet(isPresented: $aiSettingsPresented) {
                    SettingsView(settings: settings, store: store, aiPlanner: aiPlanner).presentationDragIndicator(.visible)
                }
        }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, store: store, aiPlanner: aiPlanner).presentationDragIndicator(.visible) }
        .sheet(isPresented: Binding(get: { !store.placeSearchPresented && store.selectedMarker != nil && store.draft == nil && !mapEditorActive }, set: {
            if !$0, store.draft == nil, !mapEditorActive { store.selectedMarker = nil; restoreJourneyAfterMarker() }
        }), onDismiss: {
            if store.draft != nil { mapDraftReady = true }
            else { restoreJourneyAfterMarker() }
        }) {
            if let marker = store.selectedMarker {
                MarkerDetailView(store: store, marker: marker, onClose: {
                    restoreJourneyAfterMarker()
                    store.selectedMarker = nil
                }, onNavigateItinerary: {
                    expanded = true
                    markerReturnDetent = .half
                    markerReturnExpanded = true
                })
            }
        }
        .sheet(item: Binding(get: { !store.placeSearchPresented && mapDraftReady && store.selectedMarker == nil ? store.draft : nil }, set: { if mapDraftReady { store.draft = $0 } }), onDismiss: {
            mapEditorActive = false
            mapDraftReady = true
            store.draft = nil
        }) { draft in
            if UIDevice.current.userInterfaceIdiom == .pad {
                MarkerEditorView(store: store, initial: draft).id(draft.id)
                    .onAppear { store.draftExpanded = true }
            } else {
                MarkerEditorView(store: store, initial: draft).id(draft.id)
                    .presentationDetents([.medium, .large], selection: Binding(
                        get: { store.draftExpanded ? .large : .medium },
                        set: { store.draftExpanded = $0 == .large }))
                    .presentationBackgroundInteraction(.enabled)
                    .presentationDragIndicator(.visible)
            }
        }
        .onChange(of: store.placeSearchPresented) { _, open in
            withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) {
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
            if new != nil {
                let replacingDetail = store.selectedMarker != nil
                mapDraftReady = !replacingDetail
                mapEditorActive = true
                markerReturnDetent = .compact
                markerReturnExpanded = expanded
                setJourneyDetent(.compact)
                store.selectedMarker = nil
            }
        }
        .alert("无法完成操作", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("知道了", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .onChange(of: settings.planning) { _, _ in store.rebuildRoutes() }
        .onChange(of: settings.mode) { _, _ in store.rebuildRoutes() }
    }

    private func restoreJourneyAfterMarker() {
        guard store.draft == nil, !mapEditorActive, let original = markerReturnDetent else { return }
        let originalExpanded = markerReturnExpanded
        markerReturnDetent = nil
        withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) {
            sheetDetent = original
            expanded = originalExpanded
        }
    }

    private var compactJourneyHeight: CGFloat { JourneyPresentation.compactHeight }
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
                withAnimation(AppMotion.navigation(reduceMotion: reduceMotion)) { journeyPath = path }
            }
            .onChange(of: journeyPath) { previousPath, path in
                if path.count < previousPath.count, let original = routeReturnDetent {
                    routeReturnDetent = nil
                    setJourneyDetent(original)
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
                Text(journeyTitle(destination)).font(.headline).lineLimit(1).minimumScaleFactor(0.75)
                    .accessibilityIdentifier("itinerary-panel-title")
                if let day = page.day { Text(shortDate(day.date)).font(.caption).foregroundStyle(.secondary) }
            }
            Group {
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
            if let day = page.day {
                DayContentsView(store: store, day: day, onViewRoute: {
                    if !sidebar {
                        setJourneyDetent(.half)
                    }
                })
            } else if let trip = page.trip {
                JourneyDaysContents(store: store, trip: trip)
            } else {
                JourneyOverviewContents(store: store, settingsContent: { journeySettingsRow })
            }
        }.listStyle(.insetGrouped).buttonStyle(.automatic)
            .allowsHitTesting(sidebar || sheetDetent != .compact)
            .scrollContentBackground(sidebar ? .visible : .hidden)
            .contentMargins(.top, 0, for: .scrollContent).listSectionSpacing(8)
            .id(ItineraryScrollIdentity(tripID: page.trip?.id, dayID: page.day?.id))
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
                .accessibilityAction(named: "展开旅途") { if !sidebar { setJourneyDetent(.full) } }
                .accessibilityAction(named: "收起旅途") { if !sidebar { setJourneyDetent(.compact) } }
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
                        withAnimation(AppMotion.navigation(reduceMotion: reduceMotion)) { _ = journeyPath.removeLast() }
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
                withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) {
                    if sidebar { expanded = false } else { sheetDetent = .compact }
                }
            }
        } label: {
            toolbarActionIcon("plus")
                .rotationEffect(.degrees(isCollapsed ? 0 : 45))
                .animation(AppMotion.disclosure(reduceMotion: reduceMotion), value: isCollapsed)
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
                    .transition(AppMotion.workspaceTransition(edge: .trailing, reduceMotion: reduceMotion))
                    .zIndex(2)
            }
            if AIPlannerStore.entryEnabled && (!aiPresented || layout.usesSidebar) {
                Button {
                    if aiPresented { aiPlanner.close() } else { aiPlanner.presented = true }
                } label: {
                    Image(systemName: "bubble.left").font(.system(size: 20, weight: .regular)).foregroundStyle(.primary)
                        .frame(width: 48, height: 48).contentShape(Rectangle())
                }.modifier(AIEntryButtonStyle()).accessibilityLabel(aiPresented ? "收起AI助手" : "AI 助手")
                    .zIndex(3)
                    .accessibilityIdentifier("open-ai-planner")
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.trailing, 16).padding(.top, 8)
                    .transition(.opacity)
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
            .allowsHitTesting(capsulesVisible)
            .accessibilityHidden(!capsulesVisible)
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: capsulesVisible)
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: store.tripID != nil)

        }
    }

    private var compactJourneyControls: some View {
        HStack(spacing: 4) {
            Group {
            if store.trip != nil {
            Button {
                guard !journeyPath.isEmpty else { return }
                withAnimation(AppMotion.navigation(reduceMotion: reduceMotion)) { _ = journeyPath.removeLast() }
            } label: {
                toolbarActionIcon("chevron.left").frame(width: 30, height: 30)
            }.modifier(JourneyCircleButtonStyle())
                .frame(width: 44, height: 44)
                .accessibilityLabel("上一层").accessibilityIdentifier("journey-back")
            } else {
                overviewToggleButton(sidebar: false)
            }
            }.frame(width: 88, alignment: .leading)
            ZStack {
            VStack(spacing: 0) {
                compactDateNavigation
                Text(store.trip?.name ?? "我的旅途")
                    .font(store.trip == nil ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .lineLimit(1).minimumScaleFactor(store.trip == nil ? 1 : 0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("itinerary-panel-title")
                if store.trip == nil {
                    Text("旅の目的地は、まだ見ぬ地平線の向こうに")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.65).multilineTextAlignment(.center)
                        .padding(.top, 3).offset(y: 2).accessibilityIdentifier("journey-overview-subtitle")
                }
            }
            .id("\(store.tripID ?? "overview")/\(store.dayID ?? "trip")")
            .transition(.opacity)
            }
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: store.tripID)
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: store.dayID)
            .frame(maxWidth: .infinity)
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
                Button { store.select(trip: trip, focus: false) } label: {
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
                Button { store.select(trip: nil, focus: false) } label: {
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
    private var journeySettingsRow: some View {
        Button { showSettings = true } label: {
            Label("设置", systemImage: "gearshape")
                .fullRowActionLabel()
        }.buttonStyle(.plain).foregroundStyle(Theme.accent)
            .accessibilityIdentifier("itinerary-settings-bottom")
    }
    // Native toolbars provide their own padding and touch targets.
    private func toolbarActionIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .resizable().scaledToFit()
            .font(.system(size: 20, weight: .regular))
            .frame(width: 20, height: 20, alignment: .center)
    }

    private func workspacePanel(topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        panelWorkspace(sidebar: true)
        .padding(.top, topInset)
        .padding(.bottom, bottomInset)
        .padding(.leading, leftInset)
        .environment(\.colorScheme, .light).tint(Theme.cyan)
    }

    private var locationButton: some View {
        Button { location.request { store.locating = UUID() } } label: {
            Image(systemName: "location").font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.cyan)
                .frame(width: 48, height: 48).background(.white, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 5, y: 3)
        }.accessibilityLabel("定位到当前位置")
    }
    private func togglePanel() {
        withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) { expanded.toggle() }
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
}

enum JourneyDestination: Hashable {
    case trip(String)
    case day(String, String)
}

private struct AIEntryButtonStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.buttonStyle(AIEntryPressStyle()).glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.buttonStyle(AIEntryPressStyle()).background(.regularMaterial, in: Circle())
        }
    }
}

private struct AIEntryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}
