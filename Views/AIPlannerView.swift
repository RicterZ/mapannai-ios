import SwiftUI
import PhotosUI

enum AIComposerLayout {
    static let inset: CGFloat = 16
    static let inputCornerRadius: CGFloat = 22
}

struct AIConfigurationSection: View {
    @ObservedObject var planner: AIPlannerStore
    var showsHeading = true
    @State private var draft = AIConfiguration()
    @State private var error: String?
    @State private var saved = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeading { Text("AI 助手").font(.title3.weight(.semibold)) }
            VStack(alignment: .leading, spacing: 8) {
                Text("API 地址").font(.footnote).foregroundStyle(.secondary)
                TextField("https://api.openai.com/v1", text: $draft.baseUrl)
                    .textContentType(.URL).keyboardType(.URL)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("AI API 地址").accessibilityIdentifier("ai-api-url")
                    .frame(minHeight: 32)
            }.padding(.vertical, 4)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("API Key").font(.footnote).foregroundStyle(.secondary)
                SecureField("输入 API Key", text: $draft.apiKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("AI API Key").accessibilityIdentifier("ai-api-key")
                    .frame(minHeight: 32)
            }.padding(.vertical, 4)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("模型").font(.footnote).foregroundStyle(.secondary)
                TextField("模型名称", text: $draft.model)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .accessibilityLabel("AI 模型").accessibilityIdentifier("ai-model")
                    .frame(minHeight: 32)
            }.padding(.vertical, 4)
            Button(saved ? "已保存" : "保存 AI 配置") {
                do { try planner.saveConfiguration(draft); error = nil; saved = true }
                catch { self.error = error.localizedDescription }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundStyle(Color(uiColor: .systemBackground))
            .background(Color(uiColor: .label), in: Capsule())
            .buttonStyle(.plain).disabled(planner.busy)
            .opacity(planner.busy ? 0.5 : 1)
            .accessibilityIdentifier("ai-save-configuration").padding(.top, 8)
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
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var attachedImages: [String] = []
    @State private var uploadingPhotos = false
    @State private var photoError: String?
    @State private var uploadTask: Task<Void, Never>?

    @State private var historyPresented = false
    @State private var resetConfirmation = false
    @State private var configurationAlert = false
    @State private var following = true
    @State private var nearBottom = true
    @FocusState private var inputFocused: Bool
    private var configurationReady: Bool { (try? planner.configuration.validated()) != nil }
    private var canSend: Bool { (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachedImages.isEmpty) && !uploadingPhotos && planner.ready && configurationReady }
    private var messages: [AIMessage] { planner.conversation?.messages ?? [] }

    private func interactionCard(_ record: AIInteractionRecord) -> some View {
        AIInteractionCard(prompt: planner.interaction?.id == record.id ? planner.interaction! : record.prompt,
                          planner: planner, store: store, record: record).id(record.id)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 26) {
                            if !configurationReady {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("请先配置 AI API").font(.headline)
                                    Text("在应用设置中填写 API 地址和模型，即可开始聊天。")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                    Button("前往设置", action: onOpenSettings).accessibilityIdentifier("ai-open-settings")
                                }.accessibilityIdentifier("ai-configuration-prompt")
                            }
                            if !planner.ready {
                                Text(planner.storageError ?? "正在读取会话…").foregroundStyle(.secondary)
                                if planner.storageError != nil {
                                    Button("清空本地会话后重新开始", role: .destructive) { resetConfirmation = true }
                                }
                            }
                            if messages.isEmpty && planner.partial.isEmpty && configurationReady {
                                Text("从一个目的地，或一个想法开始。")
                                    .font(.body).foregroundStyle(.secondary).padding(.top, 28)
                            }
                            ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                                ForEach(planner.conversation?.interactions?.filter { $0.messageIndex == index } ?? []) { record in
                                    interactionCard(record)
                                }
                                if message.role == "user", let content = message.content, !content.isEmpty {
                                    HStack {
                                        Spacer(minLength: 40)
                                        VStack(alignment: .leading, spacing: 10) {
                                        Text(content).font(.body).textSelection(.enabled)
                                        if let images = message.images, !images.isEmpty {
                                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                                ForEach(Array(images.enumerated()), id: \.offset) { _, url in
                                                    attachmentImage(url).frame(height: 116).clipped().clipShape(RoundedRectangle(cornerRadius: 10))
                                                }
                                            }
                                        }
                                        }
                                            .padding(.horizontal, 16).padding(.vertical, 12)
                                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 19))
                                            .frame(maxWidth: geometry.size.width * 0.8, alignment: .trailing)
                                            .accessibilityIdentifier("ai-user-bubble")
                                    }
                                } else if message.role == "assistant" {
                                    if message.tool_calls?.isEmpty == false {
                                        let start = messages.indices.prefix(index).last { messages[$0].role == "user" }.map { $0 + 1 } ?? 0
                                        let nextUser = messages.indices.dropFirst(index + 1).first { messages[$0].role == "user" } ?? messages.count
                                        let turn = Array(messages[start..<nextUser])
                                        if !messages[start..<index].contains(where: { $0.tool_calls?.isEmpty == false }) {
                                            AIToolProcess(calls: turn.flatMap { $0.tool_calls ?? [] }, results: turn)
                                        }
                                    }
                                    if let content = message.content, !content.isEmpty {
                                        assistant(content, width: min(720, geometry.size.width) - 40, copy: !planner.busy)
                                    }
                                }
                            }
                            if !planner.partial.isEmpty {
                                assistant(planner.partial, width: min(720, geometry.size.width) - 40, copy: false)
                            }
                            ForEach(planner.conversation?.interactions?.filter { $0.messageIndex >= messages.count } ?? []) { record in
                                interactionCard(record)
                            }
                            if planner.busy {
                                HStack(spacing: 8) {
                                    ProgressView().controlSize(.mini)
                                    Text(planner.status).font(.caption).foregroundStyle(.secondary)
                                }.accessibilityIdentifier("ai-processing")
                            }
                            if let error = planner.error {
                                Text(error).font(.footnote).foregroundStyle(.secondary)
                                    .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                                    .accessibilityIdentifier("ai-error")
                            }
                            if let error = planner.storageError { Text(error).font(.footnote).foregroundStyle(.secondary) }
                            Color.clear.frame(height: 1).id("ai-bottom")
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: AIChatBottom.self, value: g.frame(in: .named("ai-scroll")).maxY)
                                })
                        }
                        .padding(.horizontal, 20).padding(.vertical, 20)
                        .frame(maxWidth: 720).frame(maxWidth: .infinity)
                        .background(ArchiveKeyboardDismissal())
                        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
                            if following { proxy.scrollTo("ai-bottom", anchor: .bottom) }
                        }
                    }
                    .coordinateSpace(name: "ai-scroll")
                    .accessibilityIdentifier("ai-message-list")
                    .scrollDismissesKeyboard(.interactively)
                    .simultaneousGesture(DragGesture().onChanged { _ in following = false }.onEnded { _ in
                        following = nearBottom
                    })
                    .onPreferenceChange(AIChatBottom.self) { bottom in
                        nearBottom = bottom <= geometry.size.height + 80
                    }
                    .onAppear { proxy.scrollTo("ai-bottom", anchor: .bottom) }
                    .onChange(of: planner.activeID) { _, _ in
                        following = true; proxy.scrollTo("ai-bottom", anchor: .bottom)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        if following { proxy.scrollTo("ai-bottom", anchor: .bottom) }
                    }
                    .onChange(of: geometry.size.height) { _, _ in
                        if following { proxy.scrollTo("ai-bottom", anchor: .bottom) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !nearBottom {
                            Button {
                                following = true; proxy.scrollTo("ai-bottom", anchor: .bottom)
                            } label: {
                                Image(systemName: "arrow.down").font(.system(size: 15))
                                    .frame(width: 36, height: 36)
                                    .background(.regularMaterial, in: Circle())
                                    .frame(width: 44, height: 44)
                            }.buttonStyle(.plain).padding(16)
                                .accessibilityLabel("跳到最新").accessibilityIdentifier("ai-jump-latest")
                        }
                    }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
            .navigationTitle(planner.conversation?.title == "新会话" ? "聊聊下一程" : planner.conversation?.title ?? "聊聊下一程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: close) {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .regular))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("返回").accessibilityIdentifier("ai-close")
                }.journeyBareBackground
                ToolbarItem(placement: .topBarTrailing) {
                    Button { inputFocused = false; historyPresented = true } label: {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 16, weight: .regular))
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .disabled(planner.busy).accessibilityLabel("会话记录").accessibilityIdentifier("ai-conversations")
                }.journeyBareBackground
            }
            .edgeAttachedPanel(isPresented: $historyPresented, dimsBackground: true, backgroundColor: .systemBackground) {
                AIConversationList(planner: planner, store: store, onClose: { historyPresented = false })
            }
            .sheet(isPresented: $resetConfirmation) {
                DeletionConfirmationView(store: store, title: "清空本地会话", message: "只移除本设备聊天记录，已保存的地点和行程不受影响。", kind: "ai-history", offersExclusiveMarkers: false, independentOfAPISaving: true) { _ in
                    planner.clearUnreadableHistory()
                }
            }
        }
        .tint(Color(uiColor: .label))
        .simultaneousGesture(DragGesture(minimumDistance: 20).onEnded { value in
            guard !historyPresented, value.startLocation.x < 28,
                  value.translation.width > 80,
                  value.translation.width > abs(value.translation.height) * 2 else { return }
            close()
        })
        .accessibilityIdentifier("ai-planner-panel")
        .onAppear {
            if let pending = planner.pendingConfigurationPrompt {
                text = pending
                planner.pendingConfigurationPrompt = nil
                configurationAlert = true
            }
        }
        .appAlert(isPresented: $configurationAlert, title: "AI 尚未配置", symbol: "info.circle", message: "请在应用设置中配置 AI API 和模型。你的输入已保留，配置后可继续发送。", actions: [
            AppAlertAction(title: "取消") { configurationAlert = false },
            AppAlertAction(title: "前往设置") { configurationAlert = false; onOpenSettings() }
        ])
        #if DEBUG
        .task {
            if store.demo && ProcessInfo.processInfo.arguments.contains("--ai-stream-preview") { await planner.previewStreamingReply() }
        }
        #endif
    }

    private func close() {
        inputFocused = false
        planner.close()
    }

    private func assistant(_ content: String, width: CGFloat, copy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            AIMessageMarkdown(content: content, availableWidth: max(1, width))
                .font(.body).lineSpacing(5).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("ai-assistant-bubble")
            if copy {
                Button { UIPasteboard.general.string = content } label: {
                    Label("复制", systemImage: "square.on.square").font(.caption).foregroundStyle(.secondary)
                }.buttonStyle(.plain).frame(minHeight: 32).accessibilityIdentifier("ai-copy-answer")
            }
        }
    }

    private func attachmentImage(_ url: String) -> some View {
        AsyncImage(url: URL(string: url)) { image in image.resizable().scaledToFill() }
            placeholder: { ZStack { Color(uiColor: .tertiarySystemFill); Image(systemName: "photo").foregroundStyle(.secondary) } }
    }
    private func uploadPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, !uploadingPhotos else { return }
        let client = store.api, revision = store.settings.revision, conversation = planner.activeID
        uploadingPhotos = true; photoError = nil
        uploadTask = Task {
            defer { uploadingPhotos = false; selectedPhotos = []; uploadTask = nil }
            for item in items.prefix(max(0, 4 - attachedImages.count)) {
                do {
                    guard !store.demo else { throw AppError.message("示例模式不上传图片") }
                    guard let bytes = try await item.loadTransferable(type: Data.self), bytes.count <= 30 * 1024 * 1024 else { throw AppError.message("请选择30MB以内的照片") }
                    let compressed = try await Task.detached(priority: .userInitiated) { try MarkerImageCompression.jpeg(from: bytes) }.value
                    try Task.checkCancellation()
                    let url = try await client.uploadImage(compressed)
                    try Task.checkCancellation()
                    guard revision == store.settings.revision, conversation == planner.activeID else { return }
                    guard URL(string: url)?.scheme == "https", url.count <= 4096 else { throw AppError.message("图片地址必须为HTTPS") }
                    attachedImages.append(url)
                } catch {
                    if !Task.isCancelled, revision == store.settings.revision { photoError = "图片上传失败，请重新选择重试" }
                    return
                }
            }
        }
    }
    private var composer: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !attachedImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, url in
                            attachmentImage(url).frame(width: 68, height: 68).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(alignment: .topTrailing) {
                                    Button { attachedImages.remove(at: index) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.65))
                                            .frame(width: 32, height: 32)
                                    }.buttonStyle(.plain).accessibilityLabel("移除图片")
                                }
                        }
                    }.padding(.horizontal, 14).padding(.top, 12)
                }
            }
            if uploadingPhotos { Label("正在添加照片…", systemImage: "photo").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.top, 10) }
            if let photoError { Text(photoError).font(.caption).foregroundStyle(.red).padding(.horizontal, 16).padding(.top, 8) }
        HStack(alignment: .bottom, spacing: 4) {
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(1, 4 - attachedImages.count), matching: .images) {
                Image(systemName: "photo.badge.plus").font(.system(size: 20)).foregroundStyle(.secondary)
                    .frame(width: 44, height: 52).contentShape(Rectangle())
            }.disabled(planner.busy || uploadingPhotos || attachedImages.count >= 4)
                .accessibilityLabel("添加照片").accessibilityIdentifier("ai-add-photo")
            TextField("想继续聊些什么？", text: $text, axis: .vertical)
                .lineLimit(1...5).focused($inputFocused).font(.body)
                .padding(.leading, 2).padding(.vertical, 15)
                .accessibilityIdentifier("ai-message-input")
            Button {
                if planner.busy { planner.stop() }
                else {
                    planner.send(text, images: attachedImages, store: store)
                    if planner.busy { text = ""; attachedImages = []; photoError = nil; inputFocused = false; following = true }
                }
            } label: {
                Group {
                    if planner.busy {
                        Image(systemName: "stop.fill").font(.system(size: 11))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28).background(Color.red, in: Circle())
                    } else { Image(systemName: "paperplane").font(.system(size: 20)).foregroundStyle(.secondary) }
                }.frame(width: 44, height: 52).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!planner.busy && !canSend)
                .accessibilityLabel(planner.busy ? "停止回复" : "发送")
                .accessibilityIdentifier(planner.busy ? "ai-stop" : "ai-send")
        }
        .padding(.trailing, 5)
        }
        .onChange(of: selectedPhotos) { _, items in uploadPhotos(items) }
        .onChange(of: planner.activeID) { _, _ in uploadTask?.cancel(); attachedImages = []; photoError = nil }
        .onChange(of: store.settings.revision) { _, _ in uploadTask?.cancel(); attachedImages = []; photoError = nil }
        .onDisappear { uploadTask?.cancel() }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Color(uiColor: .separator).opacity(0.15), lineWidth: 0.5) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ai-message-composer")
        .frame(maxWidth: 720).padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }
}

private struct AIChatBottom: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct AIToolProcess: View {
    let calls: [AIMessage.ToolCall]
    let results: [AIMessage]
    @State private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 7) {
                    Text("工具过程 · \(calls.count) 项")
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }.font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("ai-tool-process-toggle")
                .accessibilityValue(expanded ? "已展开" : "已收起")
            if expanded {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(calls, id: \.id) { call in
                    let result = results.first { $0.role == "tool" && $0.tool_call_id == call.id }
                    VStack(alignment: .leading, spacing: 4) {
                    Label(AIToolLabel.text(call.function.name) + (result == nil ? " · 结果待确认" : " · 已返回结果"),
                          systemImage: result == nil ? "ellipsis" : "checkmark")
                        .font(.caption).foregroundStyle(.secondary)
                    if let summary = result?.interactionSummary {
                        Text(summary).font(.caption).foregroundStyle(.secondary)
                    }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(.top, 8)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12)
            .overlay(alignment: .leading) { Rectangle().fill(Color(uiColor: .separator).opacity(0.4)).frame(width: 1) }
            .accessibilityIdentifier("ai-tool-process")
    }
}

struct AIConversationList: View {
    @ObservedObject var planner: AIPlannerStore
    @ObservedObject var store: AppStore
    var onClose: () -> Void
    var onSelect: () -> Void = {}
    @State private var deletingID: UUID?
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("对话").font(.title2.weight(.semibold)).accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    let previous = planner.activeID; planner.newConversation()
                    if previous != planner.activeID { onSelect(); onClose() }
                } label: {
                    Label("新建", systemImage: "square.and.pencil").font(.subheadline.weight(.medium))
                        .frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(planner.busy || !planner.ready)
                    .accessibilityIdentifier("ai-new-conversation")
            }.padding(.horizontal, 20)
            ScrollView {
                VStack(spacing: 12) {
                    if planner.conversations.isEmpty { Text("还没有会话").foregroundStyle(.secondary).padding(32) }
                    ForEach(planner.conversations) { conversation in
                        Button {
                            guard !planner.busy else { return }
                            planner.activeID = conversation.id; planner.error = nil; onSelect(); onClose()
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(conversation.title).font(.body.weight(.semibold)).lineLimit(2)
                                    Spacer()
                                    if planner.activeID == conversation.id { Image(systemName: "checkmark").font(.subheadline).foregroundStyle(.secondary) }
                                }
                                if planner.activeID == conversation.id { Text("当前对话").font(.caption).foregroundStyle(.secondary) }
                            }.padding(18).frame(maxWidth: .infinity, minHeight: 68, alignment: .leading)
                                .background(Color(uiColor: planner.activeID == conversation.id ? .systemBackground : .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
                                .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color(uiColor: .separator).opacity(planner.activeID == conversation.id ? 0.6 : 0), lineWidth: 1) }
                                .contentShape(RoundedRectangle(cornerRadius: 20))
                        }.buttonStyle(.plain).disabled(planner.busy)
                            .accessibilityLabel(conversation.title)
                            .contextMenu {
                                Button("删除会话", systemImage: "trash", role: .destructive) { deletingID = conversation.id }
                                    .disabled(planner.busy)
                            }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
            }.accessibilityIdentifier("ai-conversation-list")
        }.padding(.top, 8)
            .background { Color(uiColor: .systemBackground).ignoresSafeArea() }
            .tint(Color(uiColor: .label))
            .sheet(isPresented: Binding(get: { deletingID != nil }, set: { if !$0 { deletingID = nil } })) {
                if let id = deletingID {
                    DeletionConfirmationView(store: store, title: "删除会话", message: "只删除本设备聊天记录，保留已保存的地点和行程。", kind: "ai-conversation", offersExclusiveMarkers: false, independentOfAPISaving: true) { _ in
                        guard !planner.busy else { return }
                        let previous = planner.activeID
                        planner.activeID = id; planner.deleteConversation()
                        if let previous, previous != id, planner.conversations.contains(where: { $0.id == previous }) { planner.activeID = previous }
                        deletingID = nil
                    }
                    .disabled(planner.busy)
                }
            }
    }
}
