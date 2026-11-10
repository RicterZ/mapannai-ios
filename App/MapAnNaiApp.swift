import SwiftUI

@main struct MapAnNaiApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings: Settings
    @StateObject private var store: AppStore
    @State private var launchVisible = true
    @State private var launchExiting = false
    @State private var launchAnimationFinished = false
    @State private var initialConnectionFinished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: AppStore(settings: settings))
    }
    var body: some Scene {
        WindowGroup {
            ZStack {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--marker-scope-review"), let marker = store.markers.first(where: { $0.id == (ProcessInfo.processInfo.environment["REVIEW_MARKER_ID"] ?? "demo-1") }) {
                    MarkerDetailView(store: store, marker: marker, edgeAttached: true,
                        usesDayContext: ProcessInfo.processInfo.arguments.contains("--note-context-review"),
                        noteTripID: ProcessInfo.processInfo.environment["REVIEW_MARKER_ID"] == nil ? nil : store.trips.first?.id,
                        onClose: {}, onNavigateItinerary: {})
                        .overlay(alignment: .bottom) {
                            if ProcessInfo.processInfo.arguments.contains("--note-context-review") {
                                Button("切换当前旅行") { store.dayID = nil; store.tripID = "next-year" }
                                    .accessibilityIdentifier("review-switch-trip")
                            }
                        }.zIndex(100)
                }
                if ProcessInfo.processInfo.arguments.contains("--journey-guide-entry-review"), let trip = store.trips.first {
                    NavigationStack { JourneyDaysContents(store: store, trip: trip) }.zIndex(100)
                }
                if ProcessInfo.processInfo.arguments.contains("--journey-guide-review"), let trip = store.trips.first {
                    JourneyGuideReview(store: store, trip: trip).zIndex(100)
                }
                if ProcessInfo.processInfo.arguments.contains("--temperature-review") {
                    DayTemperatureReview().zIndex(100)
                }
                if ProcessInfo.processInfo.arguments.contains("--widget-style-review") {
                    WidgetStyleReview().zIndex(100)
                }
                #endif
                if !ProcessInfo.processInfo.arguments.contains("--marker-scope-review") && !ProcessInfo.processInfo.arguments.contains("--journey-guide-entry-review") && !ProcessInfo.processInfo.arguments.contains("--journey-guide-review") && !ProcessInfo.processInfo.arguments.contains("--widget-style-review") && !ProcessInfo.processInfo.arguments.contains("--temperature-review") {
                HomeView(store: store, settings: settings)
                    .allowsHitTesting(!launchVisible)
                    .accessibilityHidden(launchVisible)
                }
                if launchVisible {
                    GeometryReader { geometry in
                        LaunchMapView()
                            .opacity(reduceMotion && launchExiting ? 0 : 1)
                            .offset(y: launchExiting && !reduceMotion
                                ? geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom : 0)
                            .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.3), value: launchExiting)
                    }.zIndex(1)
                }
            }
                .tint(Theme.accent).preferredColorScheme(.light)
                .task {
                    if !store.demo { await store.connect() }
                    initialConnectionFinished = true
                    finishLaunchIfReady()
                }
                .task {
                    do { try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 950)) }
                    catch { return }
                    launchAnimationFinished = true
                    finishLaunchIfReady()
                }
                .onChange(of: store.hasLoadedJourneySnapshot) { _, _ in finishLaunchIfReady() }
                .task(id: launchExiting) {
                    guard launchExiting else { return }
                    do { try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 300)) }
                    catch { return }
                    launchVisible = false
                }
                .task(id: scenePhase) {
                    if scenePhase == .active && !store.demo { await store.runBackgroundUpdates() }
                }
        }
    }
    private func finishLaunchIfReady() {
        guard launchVisible, !launchExiting, launchAnimationFinished,
              store.hasLoadedJourneySnapshot || initialConnectionFinished else { return }
        launchExiting = true
    }
}
