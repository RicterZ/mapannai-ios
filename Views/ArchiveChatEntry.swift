import SwiftUI
import UIKit

struct ArchiveChatEntry: View {
    @ObservedObject var planner: AIPlannerStore
    @ObservedObject var store: AppStore
    let mapVisible: Bool
    var snapshotOnly = false
    @State private var text = ""
    @State private var historyPresented = false
    @State private var resumeAfterHistory = false
    @FocusState private var inputFocused: Bool
    @ScaledMetric(relativeTo: .title2) private var headingSize = 24
    @ScaledMetric(relativeTo: .body) private var inputHeight = 84
    private var configurationReady: Bool { (try? planner.configuration.validated()) != nil }
    private var input: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        // ImageRenderer draws the panel's hosted UIKit presenter as a placeholder.
        if snapshotOnly { content } else {
            content.edgeAttachedPanel(isPresented: $historyPresented, dimsBackground: true, backgroundColor: .systemBackground, onDismiss: {
                if resumeAfterHistory { resumeAfterHistory = false; planner.presented = true }
            }) {
                AIConversationList(planner: planner, store: store, onClose: { historyPresented = false }) { resumeAfterHistory = true }
            }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("聊聊下一程").font(.system(size: headingSize, weight: .semibold))
                Spacer(minLength: 8)
                if !planner.conversations.isEmpty {
                Button { inputFocused = false; historyPresented = true } label: {
                    Label("会话记录", systemImage: "clock.arrow.circlepath")
                        .font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.trailing, -10)
                    .accessibilityIdentifier("archive-chat-history")
                }
            }
            Text("目的地、想做的事，或一个想法。")
                .font(.subheadline).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                if snapshotOnly {
                    Text(text.isEmpty ? "想去哪儿，或想怎么走？" : text)
                        .font(.body).foregroundStyle(text.isEmpty ? .tertiary : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField("想去哪儿，或想怎么走？", text: $text)
                        .font(.body).focused($inputFocused).submitLabel(.send)
                        .onSubmit(submit).accessibilityIdentifier("archive-chat-input")
                }
                if !input.isEmpty {
                    Button(action: submit) {
                        Image(systemName: "paperplane")
                            .font(.system(size: 19, weight: .regular))
                            .foregroundStyle(.secondary)
                            .frame(width: 44, height: 44).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(!planner.ready || planner.busy)
                        .accessibilityLabel("发送").accessibilityIdentifier("archive-chat-send")
                }
            }.padding(.leading, 17).padding(.trailing, input.isEmpty ? 17 : 7)
                .frame(minHeight: inputHeight)
                .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
                .id("archive-chat-input-area")
            if let recent = planner.busy ? planner.conversation : planner.conversations.first {
                Button {
                    inputFocused = false
                    Task { @MainActor in
                        if !planner.busy { planner.activeID = recent.id; planner.error = nil }
                        planner.presented = true
                    }
                } label: {
                    HStack {
                        Text((planner.busy ? "正在回复 · " : "上次聊到 · ") + recent.title).lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }.font(.subheadline).foregroundStyle(.secondary).frame(minHeight: 44)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("archive-chat-recent")
            }
        }
    }

    private func submit() {
        guard !input.isEmpty, planner.ready, !planner.busy else { return }
        guard configurationReady else {
            inputFocused = false
            planner.pendingConfigurationPrompt = input
            planner.presented = true
            return
        }
        // Do not append a home prompt to the previously viewed conversation.
        let previousID = planner.activeID
        planner.newConversation()
        guard planner.activeID != previousID else { return }
        inputFocused = false
        planner.send(input, store: store)
        planner.presented = true
        if planner.error == nil { text = "" }
    }
}

struct ArchiveKeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView { UIView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateUIView(_ view: UIView, context: Context) {
        let coordinator = context.coordinator
        DispatchQueue.main.async {
            guard view.window != nil else { return }
            var ancestor = view.superview
            while let current = ancestor {
                if let scroll = current as? UIScrollView { coordinator.attach(to: scroll); break }
                ancestor = current.superview
            }
        }
    }
    static func dismantleUIView(_ view: UIView, coordinator: Coordinator) { coordinator.detach() }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var host: UIView?
        private lazy var tap: UITapGestureRecognizer = {
            let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            return tap
        }()
        func attach(to view: UIView) {
            guard host !== view else { return }
            detach(); host = view; view.addGestureRecognizer(tap)
        }
        func detach() { host?.removeGestureRecognizer(tap); host = nil }
        @objc private func dismissKeyboard() { host?.endEditing(true) }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView { return false }
                view = current.superview
            }
            return true
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
    }
}
