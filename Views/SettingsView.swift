import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: AppStore
    @ObservedObject var aiPlanner: AIPlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var token = ""
    @State private var localError: String?
    @State private var consent = false
    @State private var checking = false
    @State private var connectionResult: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("地图") {
                    Picker("打开地图", selection: $settings.navigationMapApp) {
                        ForEach(NavigationMapApp.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.accessibilityIdentifier("navigation-map-picker")
                }
                Section("地图底图") {
                    Picker("底图", selection: $settings.mapRenderer) {
                        Text("高德地图").tag(MapRendererKind.amap)
                        Text("系统地图").tag(MapRendererKind.apple)
                        Text("Google 地图").tag(MapRendererKind.google)
                    }.accessibilityIdentifier("map-renderer-picker")
                }
                Section("路线规划") {
                    Toggle("路线规划", isOn: $settings.planning).accessibilityIdentifier("planning-toggle")
                    if settings.planning {
                        if !store.routeProgress.isEmpty {
                            HStack { ProgressView(); Text("正在规划").font(.subheadline).foregroundStyle(.secondary) }
                        }
                        if store.routeError != nil {
                            Button("重试") { store.rebuildRoutes() }
                        }
                    }
                }
                Section {
                    TextField("https://map.example.com", text: $url).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("API token（可留空）", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("MapAnNai 服务") } footer: { Text("可先留空服务地址，只开启原生地图。填写现有 Web 服务的根地址后，地点与旅行会和网页共享；token 保存在系统钥匙串。HTTP 可用于局域网开发，公网建议使用 HTTPS。") }
                Section("AI 助手") {
                    Toggle("隐藏 AI 对话图标", isOn: $settings.hideAIChatIcon)
                        .accessibilityIdentifier("hide-ai-chat-icon-toggle")
                }
                AIConfigurationSection(planner: aiPlanner)
                Section {
                    Toggle("同意高德地图隐私说明", isOn: $consent)
                    Link("查看高德隐私政策", destination: URL(string: "https://lbs.amap.com/pages/privacy/")!)
                    Text("高德 SDK 将处理设备信息、网络信息与地图交互信息。启动时请求定位权限，用于将地图移到最近的已保存地点；定位按钮可再次显示当前位置。未同意前不会初始化地图 SDK。")
                        .font(.caption).foregroundStyle(.secondary)
                } header: { Text("地图隐私") }
                Section {
                    Button {
                        Task {
                            checking = true; connectionResult = nil; localError = nil
                            defer { checking = false }
                            do {
                                let normalized = try Settings.normalizedURL(url)
                                let _: [Trip] = try await APIClient(baseURL: normalized, token: token.trimmingCharacters(in: .whitespacesAndNewlines)).request("trips")
                                try settings.save(url: normalized, token: token)
                                settings.setPrivacyAccepted(consent)
                                await store.connect()
                                connectionResult = "服务连接成功"
                            } catch { localError = error.localizedDescription }
                        }
                    } label: { HStack { Text("保存并测试服务连接"); if checking { Spacer(); ProgressView() } } }.disabled(checking || store.saving)
                    if let connectionResult { Label(connectionResult, systemImage: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                    if let localError { Text(localError).foregroundStyle(.red).font(.footnote) }
                }
                Section {
                    Link("RicterZ/mapannai-plus", destination: URL(string: "https://github.com/RicterZ/mapannai-plus")!)
                        .accessibilityIdentifier("about-web-repository")
                    Link("RicterZ/mapannai-ios", destination: URL(string: "https://github.com/RicterZ/mapannai-ios")!)
                        .accessibilityIdentifier("about-ios-repository")
                    LabeledContent("LICENSE", value: "MIT")
                        .accessibilityIdentifier("about-license")
                } header: { Text("MapAnNai") }
            }.navigationTitle("连接设置").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PanelCloseToolbarItem(identifier: "close-settings", disabled: checking) { dismiss() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            do {
                                let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : try Settings.normalizedURL(url)
                                let reconnect = normalized != settings.baseURL || token.trimmingCharacters(in: .whitespacesAndNewlines) != settings.token
                                try settings.save(url: url, token: token)
                                settings.setPrivacyAccepted(consent)
                                if reconnect { Task { await store.connect() } }
                                dismiss()
                            } catch { localError = error.localizedDescription }
                        } label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("完成")
                            .disabled(store.saving || checking)
                    }
                }
        }.onAppear { url = settings.baseURL; token = settings.token; consent = settings.privacyAccepted }
    }
}
