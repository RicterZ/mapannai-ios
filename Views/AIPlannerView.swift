import SwiftUI

struct AIConfigurationSection: View {
    @ObservedObject var planner: AIPlannerStore
    @State private var draft = AIConfiguration()
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        Section("AI 助手") {
            TextField("https://api.openai.com/v1", text: $draft.baseUrl)
                .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("ai-api-url")
            SecureField("API Key", text: $draft.apiKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-api-key")
            TextField("模型名称", text: $draft.model)
                .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-model")
            Button(saved ? "已保存" : "保存 AI 配置") {
                do { try planner.saveConfiguration(draft); error = nil; saved = true }
                catch { self.error = error.localizedDescription }
            }.disabled(planner.busy).accessibilityIdentifier("ai-save-configuration")
            if let error { Text(error).foregroundStyle(.red).font(.footnote) }
        }
        .onAppear { draft = planner.configuration }
        .onChange(of: draft) { _, _ in saved = false }
    }
}

struct AIPlannerView: View {
    @ObservedObject var planner: AIPlannerStore
    @ObservedObject var store: AppStore
    var onOpenSettings: () -> Void = {}
    @State private var text = ""
    @State private var deleteConfirmation = false
    @State private var resetConfirmation = false
    @FocusState private var inputFocused: Bool
    private var configurationReady: Bool { (try? planner.configuration.validated()) != nil }
    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && planner.ready && configurationReady }

    private func composerIcon(_ symbol: String, active: Bool, stopping: Bool = false) -> some View {
        Image(systemName: symbol)
            .font(.system(size: stopping ? 13 : 16, weight: .medium))
            .foregroundStyle(active ? (stopping ? Color.primary : Color.accentColor) : Color(uiColor: .tertiaryLabel))
            .frame(width: 28, height: 28)
            .background(active ? (stopping ? Color(uiColor: .tertiarySystemFill) : Color.accentColor.opacity(0.08)) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .frame(width: 44, height: 44).contentShape(Rectangle())
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                Group {
                    if !configurationReady {
                        VStack(spacing: 12) {
                            Text("请先配置 AI API").font(.headline)
                            Text("在设置中填写 API 地址和模型后，即可开始规划。")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Button("前往设置", action: onOpenSettings)
                                .buttonStyle(.bordered).accessibilityIdentifier("ai-open-settings")
                        }
                        .multilineTextAlignment(.center)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("ai-configuration-prompt")
                    } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if !planner.ready {
                            Text(planner.storageError ?? "正在读取会话…").foregroundStyle(.secondary)
                            if planner.storageError != nil {
                                Button("清空本地会话后重新开始", role: .destructive) { resetConfirmation = true }
                            }
                        }
                        ForEach(Array((planner.conversation?.messages ?? []).enumerated()), id: \.offset) { _, message in
                            if ["user", "assistant"].contains(message.role), let content = message.content, !content.isEmpty {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(message.role == "user" ? "你" : "AI 助手").font(.caption).foregroundStyle(.secondary)
                                    Text(.init(content)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if !planner.partial.isEmpty { Text(.init(planner.partial)).textSelection(.enabled) }
                        if planner.busy { HStack { ProgressView(); Text(planner.status).font(.footnote).foregroundStyle(.secondary) } }
                        if let error = planner.error { Text(error).foregroundStyle(.red).font(.footnote) }
                        if let error = planner.storageError { Text(error).foregroundStyle(.secondary).font(.footnote) }
                        Color.clear.frame(height: 1).id("ai-bottom")
                    }.padding()
                }
                    }
                }
                .onChange(of: planner.conversation?.messages.count) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(alignment: .bottom, spacing: 4) {
                        TextField("输入消息…", text: $text, axis: .vertical)
                            .lineLimit(1...5).focused($inputFocused).textFieldStyle(.plain)
                            .padding(.leading, 16).padding(.vertical, 12)
                            .accessibilityIdentifier("ai-message-input")
                        if planner.busy {
                            Button { planner.stop() } label: {
                                composerIcon("stop.fill", active: true, stopping: true)
                            }.accessibilityLabel("停止回复").accessibilityIdentifier("ai-stop")
                        } else {
                            Button {
                                planner.send(text, store: store)
                                if planner.busy { text = ""; inputFocused = false }
                            } label: {
                                composerIcon("paperplane", active: canSend)
                            }
                            .disabled(!canSend)
                            .accessibilityLabel("发送").accessibilityIdentifier("ai-send")
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 4)
                    .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5) }
                    .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 12)
                    .background(.regularMaterial)
                }
            }
            .navigationTitle(planner.conversation?.title ?? "AI 助手").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("新会话", systemImage: "plus") { planner.newConversation() }
                        ForEach(planner.conversations) { conversation in
                            Button(conversation.title) { planner.activeID = conversation.id; planner.error = nil }
                        }
                        if planner.conversation != nil {
                            Button("删除当前会话", systemImage: "trash", role: .destructive) { deleteConfirmation = true }
                        }
                    } label: { Image(systemName: "bubble.left.and.bubble.right") }
                        .disabled(planner.busy).accessibilityLabel("会话记录")
                }

            }
            .alert("清空本地会话？", isPresented: $resetConfirmation) {
                Button("取消", role: .cancel) {}
                Button("清空", role: .destructive) { planner.clearUnreadableHistory() }
            } message: { Text("会移除当前服务的本地聊天记录，已保存的地点和行程不受影响。") }
            .alert("删除当前会话？", isPresented: $deleteConfirmation) {
                Button("取消", role: .cancel) {}
                Button("删除", role: .destructive) { planner.deleteConversation() }
            } message: { Text("只删除本设备聊天记录，保留已保存的地点和行程。") }
        }
        .accessibilityIdentifier("ai-planner-panel")
    }
}
