import SwiftUI

enum AIComposerLayout {
    static let inset: CGFloat = 16
    static let inputCornerRadius: CGFloat = 22
}

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
        GeometryReader { geometry in
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
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !planner.ready {
                            Text(planner.storageError ?? "正在读取会话…").foregroundStyle(.secondary)
                            if planner.storageError != nil {
                                Button("清空本地会话后重新开始", role: .destructive) { resetConfirmation = true }
                            }
                        }
                        ForEach(Array((planner.conversation?.messages ?? []).enumerated()), id: \.offset) { _, message in
                            if ["user", "assistant"].contains(message.role), let content = message.content, !content.isEmpty {
                                AIMessageBubble(content: content, isUser: message.role == "user", maxWidth: geometry.size.width * 0.8)
                            }
                        }
                        if !planner.partial.isEmpty { AIMessageBubble(content: planner.partial, isUser: false, maxWidth: geometry.size.width * 0.8) }
                        if planner.busy { HStack { ProgressView(); Text(planner.status).font(.footnote).foregroundStyle(.secondary) } }
                        if let error = planner.error { Text(error).foregroundStyle(.red).font(.footnote) }
                        if let error = planner.storageError { Text(error).foregroundStyle(.secondary).font(.footnote) }
                        Color.clear.frame(height: 1).id("ai-bottom")
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }
                .defaultScrollAnchor(.bottom)
                .scrollClipDisabled()
                .modifier(AIChatScrollEdges())
                .scrollDismissesKeyboard(.interactively)
                .onAppear { proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .onChange(of: planner.activeID) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .onChange(of: planner.ready) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .onChange(of: planner.conversation?.messages.count) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .onChange(of: planner.partial) { _, _ in proxy.scrollTo("ai-bottom", anchor: .bottom) }
                .onChange(of: inputFocused) { _, focused in if focused { proxy.scrollTo("ai-bottom", anchor: .bottom) } }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AIComposerLayout.inputCornerRadius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: AIComposerLayout.inputCornerRadius, style: .continuous).strokeBorder(Color(uiColor: .separator).opacity(0.3), lineWidth: 0.5) }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("ai-message-composer")
                    .padding(.horizontal, AIComposerLayout.inset).padding(.vertical, 12)
                    .background {
                        Rectangle().fill(.regularMaterial)
                            .mask(LinearGradient(stops: [.init(color: .clear, location: 0),
                                                         .init(color: .black, location: 0.4),
                                                         .init(color: .black, location: 1)],
                                                 startPoint: .top, endPoint: .bottom))
                            .padding(.top, -24)
                            .ignoresSafeArea(edges: .bottom)
                            .allowsHitTesting(false)
                    }
                }
            }
            .navigationTitle(planner.conversation?.title ?? "AI 助手").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { planner.close() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("关闭")
                        .accessibilityIdentifier("ai-close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("新会话", systemImage: "plus") { planner.newConversation() }
                        if planner.conversation != nil {
                            DestructiveMenuButton(title: "删除当前会话", systemImage: "trash") { deleteConfirmation = true }
                        }
                        if !planner.conversations.isEmpty {
                            Divider()
                            ForEach(planner.conversations) { conversation in
                                Button(conversation.title, systemImage: conversation.id == planner.activeID
                                       ? "checkmark.bubble" : "bubble.left") {
                                    planner.activeID = conversation.id
                                    planner.error = nil
                                }
                            }
                        }
                    } label: { Image(systemName: "bubble.left.and.bubble.right") }
                        .disabled(planner.busy).accessibilityLabel("会话记录").accessibilityIdentifier("ai-conversations")
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
}

private struct AIMessageBubble: View {
    let content: String
    let isUser: Bool
    let maxWidth: CGFloat

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if isUser { Spacer(minLength: 32) }
            Group {
                if isUser { Text(content) }
                else { AIMessageMarkdown(content: content, availableWidth: max(1, maxWidth - 28)) }
            }
            .font(.body)
            .textSelection(.enabled)
            .foregroundStyle(isUser ? Color.white : Color.primary)
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(isUser ? Color(uiColor: .systemBlue) : Color(uiColor: .systemGray5),
                        in: AIMessageBubbleShape(isUser: isUser))
            .frame(maxWidth: maxWidth, alignment: isUser ? .trailing : .leading)
            .accessibilityIdentifier(isUser ? "ai-user-bubble" : "ai-assistant-bubble")
            if !isUser { Spacer(minLength: 32) }
        }.frame(maxWidth: .infinity)
    }
}

private struct AIChatScrollEdges: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            content
        }
    }
}

/// A curved tail joins the lower corner without adding space to the text layout.
private struct AIMessageBubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: 20)
        let x = rect.maxX
        let y = rect.maxY
        // Draw the outgoing tail; mirror the complete outline for incoming messages.
        path.move(to: CGPoint(x: x - 8, y: y - 14))
        path.addCurve(to: CGPoint(x: x - 6.5, y: y + 1),
                      control1: CGPoint(x: x - 8.5, y: y - 7),
                      control2: CGPoint(x: x - 8, y: y - 2))
        // A short downward curl with minimal sideways displacement.
        path.addCurve(to: CGPoint(x: x - 8, y: y + 2),
                      control1: CGPoint(x: x - 5.8, y: y + 2.2),
                      control2: CGPoint(x: x - 6.8, y: y + 2.8))
        path.addCurve(to: CGPoint(x: x - 14, y: y - 4),
                      control1: CGPoint(x: x - 10, y: y + 1),
                      control2: CGPoint(x: x - 12, y: y - 1))
        path.addLine(to: CGPoint(x: x - 19, y: y - 9))
        path.closeSubpath()
        if !isUser {
            return path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1,
                                                  tx: rect.minX + rect.maxX, ty: 0))
        }
        return path
    }
}
