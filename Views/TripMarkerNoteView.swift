import SwiftUI

struct TripMarkerNoteSection: View {
    @ObservedObject var store: AppStore
    let tripID: String
    let marker: Marker
    @State private var editing = false
    @State private var height: CGFloat = 1
    @State private var preview: NoteImageSelection?
    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    private var note: TripMarkerNote? { trip?.note(for: marker.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                JourneyEditorHeading(title: "本次旅行笔记")
                Spacer()
                Button("编辑") { editing = true }.accessibilityIdentifier("edit-trip-marker-note")
            }
            Text(trip?.name ?? "旅行").font(.footnote).foregroundStyle(.secondary)
            if let title = note?.title, !title.isEmpty { Text(title).font(.headline) }
            if let content = note?.content, NoteContent.hasContent(content) {
                HTMLReader(html: content, contentHeight: $height, onImage: { preview = NoteImageSelection(url: $0) })
                    .frame(height: height)
            } else { Text("尚无本次旅行正文").font(.footnote).foregroundStyle(.secondary) }
        }
        .sheet(isPresented: $editing) { TripMarkerNoteEditor(store: store, tripID: tripID, marker: marker) }
        .fullScreenCover(item: $preview) { NoteImagePreview(url: $0.url) }
    }
}

struct TripMarkerNoteEditor: View {
    @ObservedObject var store: AppStore
    private struct Context {
        let tripID: String
        let marker: Marker
        let client: APIClient
        let scope: String
    }
    @State private var context: Context
    private var tripID: String { context.tripID }
    private var marker: Marker { context.marker }
    private var client: APIClient { context.client }
    private var scope: String { context.scope }
    @State private var title = ""
    @State private var content = ""
    @State private var version: String?
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var composer = false
    @State private var discard = false
    @State private var originalTitle = ""
    @State private var originalContent = ""
    private var changed: Bool { title != originalTitle || content != originalContent }
    @State private var mustRefresh = false
    @State private var latest: APIClient.NoteResponse?
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore, tripID: String, marker: Marker) {
        self.store = store
        _context = State(initialValue: Context(tripID: tripID, marker: marker, client: store.api, scope: MarkerRepository.scope(store.api)))
    }
    private var connectionMatches: Bool { scope == MarkerRepository.scope(store.api) }
    var body: some View {
        NavigationStack {
            Form {
                Section("本次旅行 · " + (store.trips.first { $0.id == tripID }?.name ?? "")) {
                    Text(marker.title).font(.subheadline).foregroundStyle(.secondary)
                    TextField("本次旅行标题（可选）", text: $title)
                        .accessibilityIdentifier("trip-note-title")
                    Button(NoteContent.hasContent(content) ? "编辑本次正文" : "编写本次正文") { composer = true }
                        .accessibilityIdentifier("trip-note-content")
                    Text("名称、位置、封面和通用攻略由所有旅行共享；此处只保存本次标题和正文。")
                        .font(.footnote).foregroundStyle(.secondary)
                }.disabled(!loaded || busy)
                if loaded {
                    Section {
                        Button("复制通用攻略到本次正文") { write(copy: true) }
                            .disabled(busy || changed || mustRefresh || NoteContent.hasContent(content))
                        Text("仅复制到空正文，保留通用攻略及本次标题。请先保存当前修改。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("刷新服务器版本（保留草稿）") { load(preservingDraft: loaded) }.disabled(busy)
                        if let latest {
                            Text("服务器标题：" + (latest.note?.title ?? "无"))
                            Text(latest.note?.content ?? "无正文").font(.footnote).lineLimit(8)
                            Button("已核对，以此版本继续编辑") {
                                version = latest.note?.updatedAt; self.latest = nil; mustRefresh = false; self.error = nil
                            }
                        }
                    }
                }
                if !connectionMatches { Text("连接已切换，请关闭此页后重新打开。草稿不会发送到其他服务器。").foregroundStyle(.red) }
            }
            .navigationTitle("旅行地点笔记").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if changed { discard = true } else { dismiss() } }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { write(copy: false) }
                        .disabled(!loaded || busy || mustRefresh || !connectionMatches || title.count > 200 || content.count > 500_000)
                        .accessibilityIdentifier("save-trip-note")
                }
            }
            .task { if !loaded { load(preservingDraft: false) } }
            .interactiveDismissDisabled(changed || busy)
            .confirmationDialog("放弃本次修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .fullScreenCover(isPresented: $composer) {
                NoteComposerPreview(placeName: title.isEmpty ? marker.title : title, address: marker.title,
                    initialHTML: content, preview: false,
                    uploadPhoto: { data in
                        guard connectionMatches else { throw CancellationError() }
                        return try await client.uploadImage(data)
                    }, onSave: { content = $0 })
            }
        }
    }
    private func load(preservingDraft: Bool) {
        guard connectionMatches, !busy else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let note = try await store.loadTripNote(tripID: tripID, markerID: marker.id, using: client)
                guard connectionMatches else { return }
                if preservingDraft { latest = APIClient.NoteResponse(note: note) }
                else { title = note?.title ?? ""; content = note?.content ?? ""; version = note?.updatedAt; originalTitle = title; originalContent = content; loaded = true; error = nil }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func write(copy: Bool) {
        guard connectionMatches, loaded, !busy, !mustRefresh else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let note = try await store.writeTripNote(tripID: tripID, markerID: marker.id, title: title,
                    content: content, version: version, copy: copy, using: client)
                guard connectionMatches else { return }
                if copy { title = note?.title ?? ""; content = note?.content ?? ""; version = note?.updatedAt; originalTitle = title; originalContent = content }
                else { dismiss() }
            } catch { self.error = error.localizedDescription; mustRefresh = true }
        }
    }
}

struct TripPlaceNotesView: View {
    @ObservedObject var store: AppStore
    let tripID: String
    @Environment(\.dismiss) private var dismiss
    private var trip: Trip? { store.trips.first { $0.id == tripID } }
    var body: some View {
        NavigationStack {
            List {
                Section("所有地点，包括已移出日程的笔记") {
                    if let trip {
                        ForEach(store.tripPlaces(trip)) { marker in
                            NavigationLink {
                                MarkerDetailView(store: store, marker: marker, embedded: true, usesDayContext: false,
                                    noteTripID: tripID, onClose: { dismiss() }, onNavigateItinerary: { dismiss() })
                            } label: { Text(trip.displayTitle(for: marker)) }
                                .accessibilityIdentifier("trip-note-place-" + marker.id)
                        }
                    }
                }
            }
            .navigationTitle("地点笔记").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }
}
