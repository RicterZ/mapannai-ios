import SwiftUI

@main struct MapAnNaiApp: App {
    @StateObject private var settings: Settings
    @StateObject private var store: AppStore
    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _store = StateObject(wrappedValue: AppStore(settings: settings))
    }
    var body: some Scene {
        WindowGroup {
            HomeView(store: store, settings: settings)
                .tint(Theme.accent).preferredColorScheme(.light)
                .task { if !store.demo { await store.connect() } }
        }
    }
}
