import SwiftUI

@MainActor protocol MapRendererFactory {
    var kind: MapRendererKind { get }
    func makeMap(store: AppStore, settings: Settings, onOpenSettings: @escaping () -> Void) -> AnyView
}
@MainActor struct AMapRendererFactory: MapRendererFactory {
    let kind: MapRendererKind = .amap
    func makeMap(store: AppStore, settings: Settings, onOpenSettings: @escaping () -> Void) -> AnyView {
        if !store.demo && (!settings.privacyAccepted || settings.amapKey.isEmpty) {
            return AnyView(MapSetupPlaceholder(needsConnection: !settings.configured, onOpenSettings: onOpenSettings))
        }
        #if targetEnvironment(simulator)
        return AnyView(PreviewMap(store: store))
        #else
        return AnyView(AMapNativeRenderer(store: store, settings: settings))
        #endif
    }
}
@MainActor enum MapRendererRegistry {
    static func renderer(for kind: MapRendererKind) -> (any MapRendererFactory)? {
        switch kind {
        case .amap: AMapRendererFactory()
        case .apple: AppleMapRendererFactory()
        case .google: GoogleMapRendererFactory()
        }
    }
}
struct MapSurface: View {
    @ObservedObject var store: AppStore
    @ObservedObject var settings: Settings
    var onOpenSettings: () -> Void
    var body: some View {
        if let renderer = MapRendererRegistry.renderer(for: settings.mapRenderer) {
            renderer.makeMap(store: store, settings: settings, onOpenSettings: onOpenSettings)
                .overlay { RouteDayPicker(store: store).ignoresSafeArea() }
        } else {
            ZStack {
                Theme.paper
                ContentUnavailableView("暂不支持此地图", systemImage: "map", description: Text("服务配置选择了 Google，当前版本尚未接入其原生 SDK。"))
            }
        }
    }
}
struct MapSetupPlaceholder: View {
    var needsConnection: Bool
    var onOpenSettings: () -> Void
    var body: some View {
        ZStack {
            Theme.paper
            VStack(spacing: 14) {
                Image(systemName: "map.fill").font(.system(size: 42)).foregroundStyle(Theme.accent)
                Text("地图未开启").font(.headline)
                if needsConnection {
                    Text("连接服务以查看地点和行程。").font(.subheadline).foregroundStyle(Theme.muted)
                    Button("连接我的服务", action: onOpenSettings).buttonStyle(.borderedProminent)
                } else {
                    Button("开启地图", action: onOpenSettings).buttonStyle(.borderedProminent)
                }
            }.padding(.horizontal, 20).offset(y: -90)
                .accessibilityElement(children: .contain).accessibilityIdentifier("map-setup-placeholder")
        }
    }
}
@MainActor enum AMapBootstrap {
    static func configure(_ settings: Settings) {
        guard settings.privacyAccepted, !settings.amapKey.isEmpty else { return }
        #if !targetEnvironment(simulator)
        MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
        MAMapView.updatePrivacyAgree(.didAgree)
        AMapServices.shared().apiKey = settings.amapKey
        AMapServices.shared().enableHTTPS = true
        #endif
    }
}
