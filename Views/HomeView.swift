import SwiftUI
import CoreLocation

struct HomeView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    // Only presentation changes invalidate Home/map; streaming tokens are observed inside the chat view.
    @State private var aiPlanner = AIPlannerStore()
    @State private var aiPresented = false
    @State private var aiSettingsPresented = false
    @State private var showSettings = false
    @State private var editorPreviewPresented = false
    @State private var noteComposerPreview = false
    @State private var mapEntered = ProcessInfo.processInfo.arguments.contains("--demo") && !ProcessInfo.processInfo.arguments.contains("--archive-preview")
    @State private var initialDayPanelReady = false
    @State private var archivePath: [JourneyDestination] = []
    @State private var creatingTrip = false
    @State private var editingTrip: Trip?
    @State private var deletingPanelDay = false
    @State private var expanded = true
    @State private var journeyAvailableHeight: CGFloat = 0
    @State private var mapBottomSafeArea: CGFloat = 0
    @State private var nativeJourneyPresented = false
    @State private var journeyPath: [JourneyDestination] = []
    @State private var journeyNavigationWidth: CGFloat = 0
    @State private var visibleDayPanelHeight: CGFloat = 0
    @State private var settledDayDetailHeight: CGFloat = 0
    @State private var sheetDetent: ItineraryDetent = .half
    @State private var routeReturnDetent: ItineraryDetent?
    @State private var journeyPanelMoving = true
    @State private var markerPanelMoving = true
    @State private var markerDetailHeight: CGFloat = 0
    @State private var markerConfirmationHeight: CGFloat?
    @State private var markerConfirmationReturnDetent: ItineraryDetent?
    @State private var markerDetailDetent: ItineraryDetent = .half
    @State private var markerReturnDetent: ItineraryDetent?
    @State private var mapDraftReady = true
    @State private var searchReturnDetent: ItineraryDetent?
    @State private var searchDraftReturnDetent: ItineraryDetent?
    @State private var searchDetent: ItineraryDetent = .half
    @State private var searchOpenedMap = false
    @State private var mapEditorActive = false
    @State private var markerReturnExpanded = true
    @StateObject private var location = LocationPermission()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack(path: $archivePath) {
            JourneyArchiveView(store: store, planner: aiPlanner, path: $archivePath, mapVisible: mapEntered, onOpenSettings: { showSettings = true }) { trip, day in
                initialDayPanelReady = false
                visibleDayPanelHeight = 0
                store.select(trip: trip, day: day)
                setJourneyDetent(day == nil ? .compact : .full)
                if day != nil { store.beginDayMapBrowsing() }
                nativeJourneyPresented = true
                mapEntered = true
            }
            .sheet(isPresented: $showSettings) { SettingsView(settings: settings, store: store, aiPlanner: aiPlanner) }
            .fullScreenCover(isPresented: $mapEntered) {
                mapWorkspace.toolbar(.hidden, for: .navigationBar)
            }
        }.tint(Color(uiColor: .label))
        .onChange(of: mapEntered) { _, entered in
            guard !entered else { return }
            // A dismissed map must not retain a detail selection for the next day entry.
            store.selectedMarker = nil
            setMarkerConfirmationHeight(nil)
            restoreJourneyAfterMarker()
        }
        .onReceive(aiPlanner.$presented.removeDuplicates()) { aiPresented = $0 }
        .fullScreenCover(isPresented: Binding(get: { aiPresented && !mapEntered }, set: { if !$0 { aiPlanner.close() } })) {
            AIPlannerView(planner: aiPlanner, store: store, onOpenSettings: { aiSettingsPresented = true })
                .sheet(isPresented: $aiSettingsPresented) {
                    SettingsView(settings: settings, store: store, aiPlanner: aiPlanner)
                }
        }

        .task(id: settings.revision) {
            await aiPlanner.configure(for: settings)
            #if DEBUG
            if store.demo && ProcessInfo.processInfo.arguments.contains("--archive-ai-preview") {
                aiPlanner.configuration = AIConfiguration(model: "preview")
                let conversation = AIConversation(title: "京都的四天慢旅行", messages: [])
                aiPlanner.conversations = [conversation]; aiPlanner.activeID = conversation.id
                if ProcessInfo.processInfo.arguments.contains("--fullscreen-chat-preview") {
                    let calls = [AIMessage.ToolCall(id: "preview-search", type: "function", function: .init(name: "search_places", arguments: "{}"))]
                    aiPlanner.conversations[0].messages = [
                        AIMessage(role: "user", content: "想去京都，四天，慢一点。"),
                        AIMessage(role: "assistant", content: nil, tool_calls: calls),
                        AIMessage(role: "tool", content: "{}", tool_call_id: "preview-search"),
                        AIMessage(role: "assistant", content: "四天可以留得从容一些。先把京都分成几片街区，每天少换一次地方。\n\n**我会这样安排**\n\n第一天 · 抵达与鸭川\n\n安顿好后，沿河散步，不赶景点。\n\n第二天 · 东山的小巷\n\n清水寺、二年坂，留一段时间喝茶。\n\n第三天 · 岚山\n\n早点去竹林，午后留给渡月桥和河边。\n\n第四天 · 咖啡与返程\n\n根据离开的时间，安排一片附近街区。\n\n你已经确定出行日期了吗？住在哪里也会影响每天的顺序。")
                    ]
                }
            }
            #endif
        }
        .onAppear {
            if store.demo, ProcessInfo.processInfo.arguments.contains("--editor-preview") { editorPreviewPresented = true }
        }
        .sheet(isPresented: Binding(get: { editorPreviewPresented && editorPreviewKind != "trip" }, set: { editorPreviewPresented = $0 })) {
            JourneyEditorPreview(store: store, kind: editorPreviewKind)
        }
        .fullScreenCover(isPresented: Binding(get: { editorPreviewPresented && editorPreviewKind == "trip" }, set: { editorPreviewPresented = $0 })) {
            JourneyEditorPreview(store: store, kind: editorPreviewKind)
        }
        .onChange(of: store.searchDetailPlace?.id) { old, current in
            if old == nil, current != nil {
                searchReturnDetent = searchDetent
                searchDetent = .half
            } else if current == nil, let previous = searchReturnDetent {
                searchReturnDetent = nil
                searchDetent = previous
            }
        }
        .onChange(of: store.draft?.id) { old, id in
            guard store.placeSearchPresented else { return }
            if old == nil, id != nil {
                searchDraftReturnDetent = searchDetent
                if searchDetent == .compact { searchDetent = .half }
            } else if id == nil, let previous = searchDraftReturnDetent {
                searchDraftReturnDetent = nil
                searchDetent = previous
            }
        }
        .onChange(of: store.placeSearchPresented) { _, open in
            if open {
                searchReturnDetent = nil
                searchDraftReturnDetent = nil
                searchDetent = .half
                if !mapEntered { searchOpenedMap = true; mapEntered = true }
            } else if searchOpenedMap {
                searchOpenedMap = false; mapEntered = false
            }
        }
    }

    private var editorPreviewKind: String {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "--editor-preview"), args.indices.contains(index + 1) else { return "trip" }
        return args[index + 1]
    }

    private var mapWorkspace: some View {
        GeometryReader { geometry in
            let sidebar = horizontalSizeClass == .regular && geometry.size.width >= 700
            Group {
                if sidebar { modalContent(mapPage, sidebar: sidebar) }
                else if store.dayMapBrowsing { modalContent(mapPage) }
                else { mapPage }
            }
                .edgeAttachedPanel(isPresented: Binding(get: { !sidebar && (nativeJourneyPresented || store.placeSearchPresented) && (store.selectedMarker == nil || store.dayMapBrowsing || store.placeSearchPresented) && !(store.dayMapBrowsing && mapEditorActive) }, set: { if !store.placeSearchPresented { nativeJourneyPresented = $0 } }), detent: Binding(get: { store.placeSearchPresented ? searchDetent : store.dayMapBrowsing && store.selectedMarker != nil ? markerDetailDetent : sheetDetent }, set: { if store.placeSearchPresented { searchDetent = store.draft != nil && $0 == .compact ? .half : $0 } else if store.dayMapBrowsing && store.selectedMarker != nil { markerDetailDetent = $0 } else { sheetDetent = $0 } }),
                    compactHeight: store.placeSearchPresented ? (store.searchDetailPlace != nil || store.draft != nil ? nil : 80 + geometry.safeAreaInsets.bottom) : store.dayMapBrowsing ? (store.selectedMarker != nil ? (markerConfirmationHeight ?? 80) + geometry.safeAreaInsets.bottom : DayMapPresentation.contentHeight + max(0, geometry.safeAreaInsets.bottom - 16)) : compactJourneyHeight,
                    canDismiss: false, backgroundColor: store.placeSearchPresented || store.dayMapBrowsing ? .systemBackground : .systemGroupedBackground, animatesPresentation: !store.dayMapBrowsing || initialDayPanelReady, topContentInset: store.placeSearchPresented ? 24 : store.dayMapBrowsing ? 14 : 24, fullTopInset: store.placeSearchPresented || store.dayMapBrowsing ? 64 : 8, onHeightChange: { height in if store.dayMapBrowsing && !store.placeSearchPresented { if store.selectedMarker != nil { markerDetailHeight = height } else { visibleDayPanelHeight = height }; initialDayPanelReady = true } }, onMotionChange: { journeyPanelMoving = $0 }, onDismiss: { if mapEditorActive && store.draft != nil { mapDraftReady = true }; if !store.placeSearchPresented { nativeJourneyPresented = true } }) {
                    ZStack {
                      Group {
                    if store.dayMapBrowsing {
                        ZStack(alignment: .top) {
                          ZStack(alignment: .top) {
                            if let trip = store.trip, let day = store.day {
                              GeometryReader { panelGeometry in
                                let halfHeight = (geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom) * 0.5
                                // Include the bottom safe area: an ignoresSafeArea extension past a frozen frame
                                // shrinks while the panel moves and resizes the paged TabView.
                                let detailHeight = max(panelGeometry.size.height + panelGeometry.safeAreaInsets.bottom, halfHeight - 14)
                                NavigationStack {
                                    DayDetailPage(store: store, trip: trip, day: day, showsNavigation: false,
                                        closeIdentifier: "map-day-close", mapIdentifier: "map-day-map",
                                        onClose: { setJourneyDetent(.compact) }, onMap: { setJourneyDetent(.compact) })
                                }
                                .ignoresSafeArea(.container, edges: .bottom)
                                // Clip during panel motion without resizing List and correcting its offset every frame.
                                .frame(height: journeyPanelMoving && settledDayDetailHeight > 0 ? settledDayDetailHeight : detailHeight, alignment: .top)
                                .onAppear { settledDayDetailHeight = detailHeight }
                                .onChange(of: detailHeight) { _, height in
                                    if !journeyPanelMoving { settledDayDetailHeight = height }
                                }
                                .onChange(of: journeyPanelMoving) { _, moving in
                                    if !moving { settledDayDetailHeight = detailHeight }
                                }
                                .fullScreenCover(item: $editingTrip) { TripEditorView(store: store, trip: $0) }
                              }
                                .opacity(dayDetailProgress)
                                .allowsHitTesting(dayDetailProgress > 0.5)
                                .accessibilityHidden(dayDetailProgress < 0.5)
                                .accessibilityIdentifier("phone-itinerary-panel")
                            }
                            DayMapJourneyView(store: store, showsGrabber: false) { store.endDayMapBrowsing(); mapEntered = false }
                                .opacity(1 - dayDetailProgress)
                                .allowsHitTesting(dayDetailProgress < 0.5)
                                .accessibilityHidden(dayDetailProgress > 0.5)
                                .frame(maxHeight: .infinity, alignment: .top)
                                .ignoresSafeArea(.container, edges: .bottom)
                          }
                          .opacity(store.selectedMarker == nil ? 1 : 0)
                          .allowsHitTesting(store.selectedMarker == nil)
                          .accessibilityHidden(store.selectedMarker != nil)
                          if let marker = store.selectedMarker {
                              MarkerDetailView(store: store, marker: marker, edgeAttached: true,
                                compact: markerDetailDetent == .compact && markerConfirmationHeight == nil, onExpand: { markerDetailDetent = .half }, onConfirmationHeight: setMarkerConfirmationHeight, onClose: {
                                  restoreJourneyAfterMarker(); store.selectedMarker = nil
                              }, onNavigateItinerary: {
                                  expanded = true; markerReturnDetent = .half; markerReturnExpanded = true
                              }).transition(.opacity)
                          }
                        }.animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: store.selectedMarker != nil)
                    } else {
                        modalContent(panelWorkspace(sidebar: false))
                            .presentationDetents([.height(compactJourneyHeight), .medium, .large], selection: nativeJourneyDetent)
                            .presentationDragIndicator(.visible)
                            .presentationBackground(.regularMaterial)
                            .presentationBackgroundInteraction(.enabled)
                            .presentationContentInteraction(.resizes)
                            .interactiveDismissDisabled()
                    }
                      }
                      .opacity(store.placeSearchPresented ? 0 : 1)
                      .allowsHitTesting(!store.placeSearchPresented)
                      .accessibilityHidden(store.placeSearchPresented)
                      if store.placeSearchPresented {
                          NavigationStack {
                              DayMarkerPicker(store: store, day: store.addPlaceDay, compact: searchDetent == .compact,
                                  onExpand: { searchDetent = .half })
                          }.ignoresSafeArea(.container, edges: searchDetent == .compact ? .bottom : [])
                              .transition(.opacity)
                      }
                    }.animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: store.placeSearchPresented)
                }
                .overlay(alignment: .bottom) {
                    // Present the initial day in the cover's own first frame. UIKit adopts it
                    // once its custom presentation is laid out, without exposing the map alone.
                    if !sidebar, store.dayMapBrowsing, sheetDetent == .full, !initialDayPanelReady,
                       let trip = store.trip, let day = store.day {
                        NavigationStack {
                            DayDetailPage(store: store, trip: trip, day: day, showsNavigation: false,
                                closeIdentifier: "initial-day-close", mapIdentifier: "initial-day-map",
                                onClose: {}, onMap: {})
                        }
                        .padding(.top, 14)
                        .background(Color(uiColor: .systemBackground), in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28))
                        .frame(height: max(80, geometry.size.height - 64) + geometry.safeAreaInsets.bottom)
                        .offset(y: geometry.safeAreaInsets.bottom)
                    }
                }
                .onChange(of: store.placeSearchPresented) { _, open in
                    if !open { nativeJourneyPresented = true }
                }
                .onAppear {
                    nativeJourneyPresented = true
                    if store.tripPlacesPreview { store.select(trip: store.trips.first, focus: false) }
                    if store.dayMapBrowsing { store.showWholeDayOnMap() }
                }
                .task {
                    guard !store.demo else { return }
                    location.requestStartupLocation { store.receiveStartupLocation($0) }
                }
                .task(id: settings.revision) {
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
                .onDisappear { aiPlanner.close(); store.endDayMapBrowsing() }
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
                        // The material covers the sheet safe areas; center controls in that same outline.
                        .offset(y: (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) * 0.5 * (1 - headerProgress))
                        .opacity(1 - headerProgress)
                        .animation(AppMotion.crossfade(reduceMotion: reduceMotion)) { content in
                            content.opacity(journeyVisible ? 1 : 0)
                        }
                        .allowsHitTesting(journeyVisible && compactNavigationVisible)
                        .accessibilityHidden(!journeyVisible || !compactNavigationVisible)
                        .transition(.identity)
                }

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(AppMotion.crossfade(reduceMotion: reduceMotion), value: store.placeSearchPresented)
            .animation(AppMotion.presentation(reduceMotion: reduceMotion), value: aiPresented)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(sidebar ? "sidebar-workspace" : "phone-itinerary-panel")
    }

    private var dayDetailProgress: Double {
        guard store.dayMapBrowsing else { return 0 }
        if visibleDayPanelHeight == 0 { return sheetDetent == .compact ? 0 : 1 }
        return min(1, max(0, (Double(visibleDayPanelHeight) - DayMapPresentation.contentHeight - 20) / 100))
    }
    private func setJourneyDetent(_ detent: ItineraryDetent) {
        withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) { sheetDetent = detent }
    }

    private var mapPage: some View {
        GeometryReader { proxy in
            let layout = MapLayout(width: proxy.size.width, height: proxy.size.height,
                                   regularWidth: horizontalSizeClass == .regular, expanded: expanded,
                                   sheetHeight: store.placeSearchPresented ? (searchDetent == .compact ? 80 : searchDetent == .half ? proxy.size.height * 0.5 : proxy.size.height) : store.dayMapBrowsing && visibleDayPanelHeight > 0 ? max(0, visibleDayPanelHeight - proxy.safeAreaInsets.bottom) : store.dayMapBrowsing && sheetDetent == .compact ? DayMapPresentation.contentHeight - 16 : sheetDetent == .compact ? compactJourneyHeight : sheetDetent == .half ? proxy.size.height * 0.5 : proxy.size.height)
            let cameraInsets = layout.insets
            mapContent(layout: layout, topInset: proxy.safeAreaInsets.top, bottomInset: proxy.safeAreaInsets.bottom, leftInset: proxy.safeAreaInsets.leading)
                .onAppear {
                    store.mapViewportInsets = cameraInsets
                    mapBottomSafeArea = proxy.safeAreaInsets.bottom
                    journeyAvailableHeight = proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                }
                .onChange(of: proxy.size) { _, size in
                    journeyAvailableHeight = size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
                }
                .onChange(of: cameraInsets) { _, insets in
                    // Keep interactive panel heights out of AppStore's global view updates.
                    guard !store.dayMapBrowsing || !journeyPanelMoving else { return }
                    if store.mapViewportInsets != insets { store.mapViewportInsets = insets }
                }
                .onChange(of: journeyPanelMoving) { _, moving in
                    if !moving, store.mapViewportInsets != cameraInsets { store.mapViewportInsets = cameraInsets }
                }
                .onChange(of: store.dayID) { _, id in
                    guard id != nil, !store.dayMapBrowsing, !store.placeSearchPresented else { return }
                    store.beginDayMapBrowsing(focus: false)
                    nativeJourneyPresented = true
                }
                .onChange(of: store.routeSelectionRequest) { _, _ in
                    store.beginDayMapBrowsing(focus: false)
                    expanded = true
                    nativeJourneyPresented = true
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
        .fullScreenCover(isPresented: $creatingTrip) { TripEditorView(store: store, trip: nil) }
        .fullScreenCover(item: Binding(get: { store.tripSaveRecovery?.trip == nil ? nil : store.tripSaveRecovery }, set: { store.tripSaveRecovery = $0 })) { value in
            TripEditorView(store: store, trip: value.trip, initial: value).presentationDragIndicator(.visible)
        }
        .fullScreenCover(item: Binding(get: { store.tripSaveRecovery?.trip == nil ? store.tripSaveRecovery : nil }, set: { store.tripSaveRecovery = $0 })) { value in
            TripCreationView(store: store, initial: value)
        }
        .fullScreenCover(item: Binding(get: { store.dayMapBrowsing ? nil : editingTrip }, set: { editingTrip = $0 })) { TripEditorView(store: store, trip: $0).presentationDragIndicator(.visible) }
        .sheet(isPresented: $deletingPanelDay) {
            if let day = store.day { DayDeletionView(store: store, day: day) }
        }
        .sheet(item: Binding(get: { store.dayEditorDraft },
            set: { store.dayEditorDraft = $0 })) { draft in
            JourneyDayEditor(store: store, draft: draft)
        }
        .fullScreenCover(isPresented: Binding(get: { aiPresented && mapEntered }, set: { if !$0 { aiPlanner.close() } })) {
            AIPlannerView(planner: aiPlanner, store: store, onOpenSettings: { aiSettingsPresented = true })
                .sheet(isPresented: $aiSettingsPresented) {
                    SettingsView(settings: settings, store: store, aiPlanner: aiPlanner).presentationDragIndicator(.visible)
                }
        }
        .sheet(isPresented: $showSettings) { SettingsView(settings: settings, store: store, aiPlanner: aiPlanner).presentationDragIndicator(.visible) }
        .edgeAttachedPanel(isPresented: Binding(get: { (sidebar || !store.dayMapBrowsing) && !store.placeSearchPresented && store.selectedMarker != nil && store.draft == nil && !mapEditorActive }, set: {
            if !$0, store.draft == nil, !mapEditorActive { store.selectedMarker = nil; restoreJourneyAfterMarker() }
        }), detent: $markerDetailDetent, compactHeight: (markerConfirmationHeight ?? 80) + mapBottomSafeArea, canDismiss: false, backgroundColor: .systemBackground, topContentInset: 14, onHeightChange: { markerDetailHeight = $0 }, onMotionChange: { markerPanelMoving = $0 }, onDismiss: {
            if store.draft != nil { mapDraftReady = true }
            else { restoreJourneyAfterMarker() }
        }) {
            if let marker = store.selectedMarker {
                MarkerDetailView(store: store, marker: marker, edgeAttached: !sidebar,
                    compact: !sidebar && markerDetailDetent == .compact && markerConfirmationHeight == nil, onExpand: { markerDetailDetent = .half }, onConfirmationHeight: setMarkerConfirmationHeight, onClose: {
                    restoreJourneyAfterMarker()
                    store.selectedMarker = nil
                }, onNavigateItinerary: {
                    store.beginDayMapBrowsing(focus: false)
                    expanded = true
                    nativeJourneyPresented = true
                    markerReturnDetent = .half
                    markerReturnExpanded = true
                })
            }
        }
        .sheet(item: Binding(get: { UIDevice.current.userInterfaceIdiom == .pad && !store.placeSearchPresented && mapDraftReady && store.selectedMarker == nil ? store.draft : nil }, set: { if mapDraftReady { store.draft = $0 } }), onDismiss: {
            mapEditorActive = false
            mapDraftReady = true
            store.draft = nil
        }) { draft in
            MarkerEditorView(store: store, initial: draft).id(draft.id)
                .onAppear { store.draftExpanded = true }
        }
        .edgeAttachedPanel(isPresented: Binding(get: {
            UIDevice.current.userInterfaceIdiom != .pad && !store.placeSearchPresented
                && mapDraftReady && store.selectedMarker == nil && store.draft != nil
        }, set: { if !$0 { store.draft = nil } }), detent: Binding(
            get: { store.draftExpanded ? .full : .half },
            set: { store.draftExpanded = $0 == .full }), canDismiss: false,
            backgroundColor: .systemBackground, topContentInset: 14,
            onDismiss: { mapEditorActive = false; mapDraftReady = true }) {
            if let draft = store.draft {
                NavigationStack {
                    MarkerEditorView(store: store, initial: draft, embedded: true)
                        .id(draft.id)
                }
            }
        }
        .onChange(of: store.selectedMarker?.id) { old, id in
            if old == nil, id != nil { markerDetailDetent = .half }
            if id == nil { setMarkerConfirmationHeight(nil) }
        }
        .onChange(of: store.draft?.id) { old, new in
            guard !store.placeSearchPresented else { return }
            if new != nil {
                store.draftExpanded = false
                let replacingDetail = store.selectedMarker != nil
                mapDraftReady = !replacingDetail
                mapEditorActive = true
                markerReturnDetent = .compact
                markerReturnExpanded = expanded
                setJourneyDetent(.compact)
                store.selectedMarker = nil
            }
        }
        .journeyError(store: store, enabled: store.dayEditorDraft == nil)
        .onChange(of: settings.planning) { _, _ in store.rebuildRoutes() }
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

    private func setMarkerConfirmationHeight(_ height: CGFloat?) {
        if let height {
            if markerConfirmationHeight == nil { markerConfirmationReturnDetent = markerDetailDetent }
            markerConfirmationHeight = height
            markerDetailDetent = .compact
        } else if markerConfirmationHeight != nil {
            markerConfirmationHeight = nil
            if let previous = markerConfirmationReturnDetent { markerDetailDetent = previous }
            markerConfirmationReturnDetent = nil
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
            journeyPage(store.trip.map { .trip($0.id) }, sidebar: sidebar)
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
                case nil:
                    store.select(trip: nil, focus: false)
                    mapEntered = false
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
                Button("编辑", systemImage: "pencil") {
                    if let trip = page.trip { store.beginDayEditor(trip: trip, day: day) }
                }
                DestructiveMenuButton(title: "删除日期", systemImage: "trash") { deletingPanelDay = true }
                    .disabled((page.trip?.days.count ?? 0) <= 1 || store.saving)
            } else if let trip = page.trip {
                Button("编辑旅途", systemImage: "pencil") { editingTrip = trip }
            }
        }
    }
    @ViewBuilder private func journeyPage(_ destination: JourneyDestination?, sidebar: Bool) -> some View {
        let page = scope(destination)
        if let trip = page.trip, let day = page.day {
            DayDetailPage(store: store, trip: trip, day: day, showsNavigation: sidebar,
                onClose: {
                    store.select(trip: trip, focus: false)
                    if !sidebar { setJourneyDetent(.compact) }
                }, onMap: {
                    store.beginDayMapBrowsing(focus: false)
                    if !sidebar { setJourneyDetent(.compact) }
                })
        } else {
          Group {
            if let trip = page.trip {
                JourneyDaysContents(store: store, trip: trip, onSelectDay: { day in
                    store.select(trip: trip, day: day, focus: false); store.beginDayMapBrowsing(); setJourneyDetent(.full)
                })
            } else {
                Color.clear
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
    }

    @ToolbarContentBuilder private func journeyToolbar(sidebar: Bool, destination: JourneyDestination?) -> some ToolbarContent {
        ToolbarItem(placement: .principal) {
            journeyHeading(destination, sidebar: sidebar).offset(y: !sidebar && sheetDetent == .compact ? 2 : 4)
                .accessibilityAction(named: "展开旅途") { if !sidebar { setJourneyDetent(.full) } }
                .accessibilityAction(named: "收起旅途") { if !sidebar { setJourneyDetent(.compact) } }
        }
        if sidebar {
            journeyLeadingControl(destination: destination, sidebar: true)
            ToolbarItem(placement: .topBarTrailing) {
                Button { togglePanel() } label: { toolbarActionIcon("sidebar.left") }
                    .accessibilityLabel("收起行程").accessibilityIdentifier("itinerary-panel-toggle")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                Button { setJourneyDetent(.compact) } label: {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .regular))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("收起旅途").accessibilityIdentifier("close-journey")
            }.journeyBareBackground
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
            if isCollapsed { mapEntered = false }
            else {
                withAnimation(AppMotion.presentation(reduceMotion: reduceMotion)) {
                    if sidebar { expanded = false } else { sheetDetent = .compact }
                }
            }
        } label: {
            toolbarActionIcon(isCollapsed ? "rectangle.stack" : "xmark")
                .animation(AppMotion.disclosure(reduceMotion: reduceMotion), value: isCollapsed)
                .frame(width: 30, height: 30)
        }.modifier(JourneyCircleButtonStyle())
            .frame(width: 44, height: 44).contentShape(Rectangle())
            .accessibilityLabel(isCollapsed ? "我的旅途" : "收起旅途")
            .accessibilityIdentifier(isCollapsed ? "compact-create-journey" : "close-journey")
    }

    private func mapContent(layout: MapLayout, topInset: CGFloat, bottomInset: CGFloat, leftInset: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            MapSurface(store: store, settings: settings, onOpenSettings: { showSettings = true })
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .ignoresSafeArea()
            if store.dayMapBrowsing && !store.placeSearchPresented && store.selectedMarker == nil {
                HStack {
                    Button {
                        mapEntered = false
                    } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44).contentShape(Rectangle()) }
                        .accessibilityLabel("返回旅途详情")
                        .accessibilityIdentifier("day-map-back")
                    Spacer()
                }.font(.system(size: 19, weight: .regular)).foregroundStyle(.primary).buttonStyle(.plain)
                    .padding(.horizontal, 16).padding(.top, 8)
            }
            if AIPlannerStore.entryEnabled && !settings.hideAIChatIcon && (!aiPresented || layout.usesSidebar) {
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
            if !layout.usesSidebar, !store.placeSearchPresented, store.selectedMarker != nil, markerDetailDetent != .full {
                Button { location.request { store.cycleLocationMode() } } label: {
                    Image(systemName: store.locationMode.symbol).font(.system(size: 19)).foregroundStyle(.primary)
                        .frame(width: 44, height: 44).background(Color(uiColor: .systemBackground), in: Circle())
                }.buttonStyle(.plain).accessibilityLabel("定位到当前位置")
                    .accessibilityIdentifier("marker-detail-location")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, max(16, markerDetailHeight - bottomInset + 16))
                    .offset(x: markerPanelMoving && !reduceMotion ? 96 : 0)
                    .opacity(markerPanelMoving ? 0 : 1)
                    .allowsHitTesting(!markerPanelMoving)
                    .accessibilityHidden(markerPanelMoving)
                    .animation(markerPanelMoving || reduceMotion ? nil : .easeOut(duration: 0.22), value: markerPanelMoving)
            }
            if !layout.usesSidebar && !store.placeSearchPresented && store.selectedMarker == nil && sheetDetent != .full {
                mapActionBar.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, max(12, (store.dayMapBrowsing && !store.placeSearchPresented && visibleDayPanelHeight > 0 ? visibleDayPanelHeight - bottomInset : CGFloat(layout.sheetHeight ?? compactJourneyHeight) - bottomInset) + 16))
                    .offset(x: journeyPanelMoving && !reduceMotion ? 96 : 0)
                    .opacity(journeyPanelMoving ? 0 : 1)
                    .allowsHitTesting(!journeyPanelMoving)
                    .accessibilityHidden(journeyPanelMoving)
                    .animation(journeyPanelMoving || reduceMotion ? nil : .easeOut(duration: 0.22), value: journeyPanelMoving)
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
        Button { setJourneyDetent(.half) } label: {
            HStack(spacing: 12) {
                Text(store.trip?.name ?? "我的旅途")
                    .font(.subheadline.weight(.semibold)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up").foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
            }.padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary)
            .accessibilityLabel("展开旅途")
    }

    private var mapActionBar: some View {
        HStack(spacing: 0) {
            Button { location.request { store.cycleLocationMode() } } label: {
                Image(systemName: store.locationMode.symbol).frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("定位到当前位置").accessibilityIdentifier("itinerary-header-location")
            Rectangle().fill(Color(uiColor: .separator).opacity(0.3)).frame(width: 0.5, height: 18)
            Button { store.beginAddingPlace(to: store.day, tripID: store.tripID) } label: {
                Image(systemName: "magnifyingglass").frame(width: 44, height: 44).contentShape(Rectangle())
            }.accessibilityLabel("搜索地点").accessibilityIdentifier("itinerary-search")
        }.font(.system(size: 19, weight: .regular)).foregroundStyle(Color(uiColor: .label))
            .buttonStyle(.plain).padding(3)
            .background(Color(uiColor: .systemBackground).opacity(0.96), in: Capsule())
            .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.06), radius: 8, y: 3)
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
                            store.beginDayMapBrowsing(focus: false)
                            nativeJourneyPresented = true
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
        Button { location.request { store.cycleLocationMode() } } label: {
            Image(systemName: store.locationMode.symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(Theme.cyan)
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
    private var onLocation: ((Coordinate) -> Void)?
    override init() { super.init(); manager.delegate = self }
    func request(_ action: @escaping () -> Void) {
        onAllowed = action
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        else if [.authorizedWhenInUse, .authorizedAlways].contains(manager.authorizationStatus) { action(); onAllowed = nil }
    }
    func requestStartupLocation(_ action: @escaping (Coordinate) -> Void) {
        guard onLocation == nil else { return }
        onLocation = action
        request { [weak self] in self?.manager.startUpdatingLocation() }
        if [.denied, .restricted].contains(manager.authorizationStatus) { onLocation = nil }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last(where: { $0.horizontalAccuracy >= 0 }) else { return }
        onLocation?(Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
        onLocation = nil
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { onLocation = nil }
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
