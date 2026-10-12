import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var store: AppStore
    @ObservedObject var aiPlanner: AIPlannerStore
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title2) private var headingSize = 22
    @State private var url = ""
    @State private var token = ""
    @State private var localError: String?
    @State private var consent = false
    @State private var checking = false
    @State private var connectionResult: String?
    @FocusState private var connectionFocused: Bool

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        mapPreferences
                        serviceConnection.id("settings-service")
                        privacy
                        about
                    }
                    .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 32)
                    .frame(maxWidth: 560).frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("settings-scroll")
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: localError) { _, error in
                    if error != nil { proxy.scrollTo("settings-service", anchor: .top) }
                }
                .background(Color(uiColor: .systemGroupedBackground))
                .navigationTitle("设置").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PanelCloseToolbarItem(identifier: "close-settings", disabled: checking) { dismiss() }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: saveAndClose) { Image(systemName: "checkmark") }
                            .accessibilityLabel("保存设置").accessibilityIdentifier("save-settings")
                            .disabled(store.saving || checking)
                    }
                }
            }
        }
        .onAppear { url = settings.baseURL; token = settings.token; consent = settings.privacyAccepted }
        .onChange(of: url) { _, _ in connectionResult = nil }
        .onChange(of: token) { _, _ in connectionResult = nil }
    }

    private var mapPreferences: some View {
        group("地图与路线") {
            card {
                LabeledContent("地图底图") {
                    Picker("地图底图", selection: $settings.mapRenderer) {
                        Text("系统地图").tag(MapRendererKind.apple)
                        Text("高德地图").tag(MapRendererKind.amap)
                        Text("Google 地图").tag(MapRendererKind.google)
                    }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("map-renderer-picker")
                }.frame(minHeight: 44)
                Divider()
                LabeledContent("导航地图") {
                    Picker("导航地图", selection: $settings.navigationMapApp) {
                        ForEach(NavigationMapApp.allCases, id: \.self) { Text($0.label).tag($0) }
                    }.labelsHidden().pickerStyle(.menu).accessibilityIdentifier("navigation-map-picker")
                }.frame(minHeight: 44)
                Divider()
                Toggle(isOn: $settings.planning) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("路线规划")
                        Text("在地图上连接行程地点").font(.footnote).foregroundStyle(.secondary)
                    }
                }.accessibilityIdentifier("planning-toggle").padding(.vertical, 4)
                if settings.planning {
                    if !store.routeProgress.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("正在规划").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    if store.routeError != nil {
                        Button("重试路线规划") { store.rebuildRoutes() }.font(.subheadline)
                    }
                }
            }
        }
    }

    private var serviceConnection: some View {
        group("服务连接") {
            card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("服务地址").font(.footnote).foregroundStyle(.secondary)
                    TextField("https://map.example.com", text: $url)
                        .focused($connectionFocused)
                        .textContentType(.URL).keyboardType(.URL)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("服务地址").accessibilityIdentifier("settings-service-url")
                        .frame(minHeight: 32)
                }.padding(.vertical, 4)
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("访问凭据").font(.footnote).foregroundStyle(.secondary)
                    SecureField("API token（可留空）", text: $token)
                        .focused($connectionFocused)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("访问凭据").accessibilityIdentifier("settings-service-token")
                        .frame(minHeight: 32)
                }.padding(.vertical, 4)
                Button(action: testConnection) {
                    HStack(spacing: 10) {
                        Text("保存并测试连接")
                        if checking { ProgressView().tint(Color(uiColor: .systemBackground)) }
                    }
                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(Color(uiColor: .systemBackground))
                    .background(Color(uiColor: .label), in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain).disabled(checking || store.saving)
                .opacity(checking || store.saving ? 0.5 : 1)
                .accessibilityIdentifier("settings-test-connection").padding(.top, 8)
                if let connectionResult {
                    Label(connectionResult, systemImage: "checkmark.circle")
                        .font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("settings-connection-result")
                }
                if let localError {
                    Text(localError).foregroundStyle(.red).font(.footnote)
                        .accessibilityIdentifier("settings-connection-error")
                }
            }
            Text("连接后，与网页共享旅途和地点。访问凭据保存在系统钥匙串。")
                .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
        }
    }

    private var privacy: some View {
        group("隐私") {
            card {
                Toggle("同意高德地图隐私说明", isOn: $consent)
                    .accessibilityIdentifier("settings-map-consent").frame(minHeight: 44)
                Text("使用高德底图前需要同意隐私说明。高德 SDK 会处理设备、网络和地图交互信息；定位需经系统授权。")
                    .font(.footnote).foregroundStyle(.secondary)
                Divider()
                Link(destination: URL(string: "https://lbs.amap.com/pages/privacy/")!) {
                    linkRow("高德隐私政策")
                }.accessibilityIdentifier("settings-privacy-policy")
            }
        }
    }

    private var about: some View {
        group("关于") {
            card {
                Text("MapAnNai").font(.title3.weight(.semibold)).padding(.vertical, 4)
                Divider()
                Link(destination: URL(string: "https://github.com/RicterZ/mapannai-plus")!) {
                    linkRow("RicterZ/mapannai-plus")
                }.accessibilityIdentifier("about-web-repository")
                Divider()
                Link(destination: URL(string: "https://github.com/RicterZ/mapannai-ios")!) {
                    linkRow("RicterZ/mapannai-ios")
                }.accessibilityIdentifier("about-ios-repository")
                Divider()
                HStack {
                    Text("开源许可")
                    Spacer()
                    Text("MIT").foregroundStyle(.secondary)
                }.frame(minHeight: 44).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("about-license")
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: headingSize, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content)
            .font(.body).padding(.horizontal, 20).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func linkRow(_ title: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right").font(.footnote).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }.frame(minHeight: 44).contentShape(Rectangle())
    }

    private func saveAndClose() {
        connectionFocused = false
        do {
            let normalized = url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : try Settings.normalizedURL(url)
            let reconnect = normalized != settings.baseURL || token.trimmingCharacters(in: .whitespacesAndNewlines) != settings.token
            try settings.save(url: url, token: token)
            settings.setPrivacyAccepted(consent)
            if reconnect { Task { await store.connect() } }
            dismiss()
        } catch { localError = error.localizedDescription }
    }

    private func testConnection() {
        connectionFocused = false
        checking = true; connectionResult = nil; localError = nil
        Task {
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
    }
}
