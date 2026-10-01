import SwiftUI

struct AIConfigurationView: View {
    @ObservedObject var planner: AIPlannerStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft = AIConfiguration()
    @State private var error: String?
    var body: some View {
        Form {
            Section {
                TextField("https://api.openai.com/v1", text: $draft.baseUrl)
                    .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityIdentifier("ai-api-url")
                SecureField("API Key", text: $draft.apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-api-key")
                TextField("模型名称", text: $draft.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("ai-model")
            } header: { Text("兼容 OpenAI 的 API") } footer: {
                Text("Key 保存在系统钥匙串。发送消息时，配置会交给你连接的 MapAnNai 服务，由服务器组装提示词、调用模型和规划工具。模型需支持工具调用。")
            }
            Section {
                Text("默认使用公共 HTTPS API。私有网络或 HTTP 模型服务需要在 MapAnNai 服务端启用 AI_ALLOW_PRIVATE_ENDPOINTS。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let error { Text(error).foregroundStyle(.red) }
        }
        .navigationTitle("AI API 配置").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    do { try planner.saveConfiguration(draft); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.disabled(planner.busy).accessibilityIdentifier("ai-save-configuration")
            }
        }
        .onAppear { draft = planner.configuration }
    }
}

struct AIPlannerView: View {
    @ObservedObject var planner: AIPlannerStore
    @ObservedObject var store: AppStore
    @State private var text = ""
    @State private var deleteConfirmation = false
    @State private var resetConfirmation = false
    @FocusState private var inputFocused: Bool
    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                .onChange(of: planner.conversation?.messages.count) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .safeAreaInset(edge: .bottom) {
                    HStack(alignment: .bottom) {
                        TextField("描述目的地、日期和偏好", text: $text, axis: .vertical)
                            .lineLimit(1...5).focused($inputFocused).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("ai-message-input")
                        if planner.busy {
                            Button { planner.stop() } label: { Image(systemName: "stop.circle.fill").font(.title2) }
                                .accessibilityLabel("停止回复").accessibilityIdentifier("ai-stop")
                        } else {
                            Button {
                                planner.send(text, store: store)
                                if planner.busy { text = ""; inputFocused = false }
                            } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !planner.ready)
                                .accessibilityLabel("发送").accessibilityIdentifier("ai-send")
                        }
                    }.padding().background(.regularMaterial)
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { AIConfigurationView(planner: planner) } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("AI API 配置")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { planner.close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭AI助手").accessibilityIdentifier("close-ai-planner")
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
