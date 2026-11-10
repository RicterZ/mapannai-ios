import SwiftUI
import PhotosUI

struct TripNoteHTML: View {
    let html: String
    @State private var height: CGFloat = 1
    @State private var preview: NoteImageSelection?
    var body: some View {
        HTMLReader(html: html, contentHeight: $height, onImage: { preview = NoteImageSelection(url: $0) })
            .frame(height: height)
            .fullScreenCover(item: $preview) { NoteImagePreview(url: $0.url) }
    }
}

struct TripMarkerNoteSection: View {
    let trip: Trip
    let marker: Marker
    private var note: TripMarkerNote? { trip.note(for: marker.id) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 4)
            Text("行程笔记").font(.footnote).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                PlaceIconView(emoji: trip.emoji ?? "✈️", size: 18)
                Text(trip.name).font(.caption).lineLimit(1)
            }.padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
            if let title = note?.title, !title.isEmpty { Text(title).font(.headline) }
            if let content = note?.content, NoteContent.hasContent(content) {
                TripNoteHTML(html: content)
            } else if note?.title.isEmpty != false {
                Text("这次旅行还没有笔记，可点右上角编辑添加").font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityIdentifier("trip-note-reading")
    }
}

/// Shared notes stay available below the selected trip without changing the map context.
struct GeneralMarkerNoteSection: View {
    let marker: Marker
    @State private var expanded = false
    @State private var preview: NoteImageSelection?
    private var content: String { NoteContent.hasContent(marker.content.markdownContent) ? marker.content.markdownContent : "" }
    private var cover: String? { PlaceImage.general(marker) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().padding(.vertical, 4)
            if content.isEmpty && cover == nil {
                JourneyEditorHeading(title: "通用笔记")
                Text("还没有通用笔记").font(.footnote).foregroundStyle(.secondary)
            } else {
                DisclosureGroup(isExpanded: $expanded) {
                    if let cover, let url = imageURL(cover) {
                        MarkerCoverBanner {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Color(uiColor: .secondarySystemBackground) }
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { preview = NoteImageSelection(url: url) }
                            .accessibilityLabel("预览通用封面").accessibilityAddTraits(.isButton)
                            .accessibilityIdentifier("marker-general-cover")
                    }
                    if !content.isEmpty { TripNoteHTML(html: content).accessibilityIdentifier("marker-general-note") }
                } label: {
                    HStack(spacing: 12) {
                        if !expanded, let cover, let url = imageURL(cover) {
                            AsyncImage(url: url) { image in image.resizable().scaledToFill() }
                                placeholder: { Color(uiColor: .secondarySystemBackground) }
                                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("通用笔记").font(.subheadline.weight(.medium))
                            if !expanded, !NoteContent.excerpt(content).isEmpty {
                                Text(NoteContent.excerpt(content)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }.padding(.vertical, 4)
                }.tint(.secondary).accessibilityIdentifier("marker-general-disclosure")
            }
        }.fullScreenCover(item: $preview) { NoteImagePreview(url: $0.url) }
    }
}

/// One sheet owns every scope, so switching never replaces a draft or its opening version.
struct MarkerScopeEditorView: View {
    @ObservedObject var store: AppStore
    private struct Context {
        let marker: Marker
        let trips: [Trip]
        let client: APIClient
        let scope: String
    }
    @State private var context: Context
    @State private var selected: String
    @State private var globalDraft: MarkerDraft
    @State private var globalBaseline: MarkerDraft
    @State private var notes: [String: TripNoteEditDraft] = [:]
    @State private var loadErrors: [String: String] = [:]
    @State private var busy = false
    @State private var globalBusy = false
    @State private var composerScope: String?
    @State private var discard = false
    @State private var status: String?
    @State private var coverPhoto: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss
    init(store: AppStore, marker: Marker, defaultTripID: String?) {
        self.store = store
        let trips = MarkerPresentation.memberships(for: marker.id, trips: store.trips).map(\.trip)
        let scope = MarkerRepository.scope(store.api)
        _context = State(initialValue: Context(marker: marker, trips: trips, client: store.api, scope: scope))
        _selected = State(initialValue: trips.first { $0.id == defaultTripID }?.id ?? "")
        var draft = MarkerDraft(marker: marker); draft.noteScope = scope
        _globalDraft = State(initialValue: draft); _globalBaseline = State(initialValue: draft)
    }
    private var connectionMatches: Bool { context.scope == MarkerRepository.scope(store.api) }
    private var working: Bool { busy || globalBusy || store.saving }
    private var changed: Bool { globalDraft != globalBaseline || notes.values.contains(where: \.changed) }
    private var selectedName: String { context.trips.first { $0.id == selected }?.name ?? "通用资料" }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Menu {
                    Button { selected = ""; status = nil } label: {
                        Label("通用资料", systemImage: selected.isEmpty ? "checkmark" : "circle")
                    }.accessibilityIdentifier("edit-scope-general")
                    ForEach(context.trips) { trip in
                        Button { selected = trip.id; status = nil } label: {
                            Label(trip.name, systemImage: selected == trip.id ? "checkmark" : "circle")
                        }.accessibilityIdentifier("edit-scope-" + trip.id)
                    }
                } label: {
                    HStack {
                        Text("编辑范围").foregroundStyle(.secondary)
                        Spacer()
                        Text(selectedName).fontWeight(.medium).lineLimit(1)
                        Image(systemName: "chevron.down").font(.caption)
                    }.padding(16).contentShape(Rectangle())
                }.disabled(working || !connectionMatches).accessibilityIdentifier("marker-edit-scope")
                if !connectionMatches {
                    Text("连接已切换，请关闭后重新打开。草稿不会发送到其他服务器。").font(.footnote).foregroundStyle(.red).padding(.horizontal)
                }
                if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                ZStack {
                    MarkerEditorView(store: store, initial: globalDraft, embedded: true,
                        onSaved: { globalBaseline = globalDraft; status = "通用资料已提交" }, scopeManaged: true,
                        onDraftChange: { globalDraft = $0 }, onBusyChange: { globalBusy = $0 })
                        .opacity(selected.isEmpty ? 1 : 0)
                        .allowsHitTesting(selected.isEmpty && connectionMatches)
                        .accessibilityHidden(!selected.isEmpty)
                    if !selected.isEmpty { noteForm }
                }
            }
            .navigationTitle("编辑地点").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { if changed { discard = true } else { dismiss() } }.disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if !selected.isEmpty {
                        Button("保存") { write(copy: false) }
                            .disabled(working || !connectionMatches || notes[selected] == nil || notes[selected]?.mustRefresh == true
                                || (notes[selected]?.title.count ?? 0) > 200 || (notes[selected]?.content.count ?? 0) > 500_000)
                            .accessibilityIdentifier("save-trip-note")
                    }
                }
            }
            .task(id: selected) { if !selected.isEmpty, notes[selected] == nil { await load(selected, preservingDraft: false) } }
            .interactiveDismissDisabled(changed || working)
            .confirmationDialog("放弃未保存的修改？", isPresented: $discard, titleVisibility: .visible) {
                Button("放弃修改", role: .destructive) { dismiss() }
            }
            .fullScreenCover(isPresented: Binding(get: { composerScope != nil }, set: { if !$0 { composerScope = nil } })) {
                if let id = composerScope, let draft = notes[id] {
                    NoteComposerPreview(placeName: draft.title.isEmpty ? context.marker.title : draft.title,
                        address: context.marker.title, initialHTML: draft.content, preview: false,
                        uploadPhoto: { data in
                            guard connectionMatches else { throw CancellationError() }
                            guard !store.demo else { throw AppError.message("只读示例不上传照片") }
                            let url = try await context.client.uploadImage(data)
                            guard connectionMatches else { throw CancellationError() }
                            return url
                        }, onSave: { notes[id]?.content = $0 })
                }
            }
        }
    }
    private var noteForm: some View {
        let id = selected
        return Form {
            Section("本次旅行 · " + selectedName) {
                Text(context.marker.title).font(.subheadline).foregroundStyle(.secondary)
                if let draft = notes[id] {
                    TextField("本次旅行显示标题（可选）", text: Binding(get: { notes[id]?.title ?? "" }, set: { notes[id]?.title = $0 }))
                        .accessibilityIdentifier("trip-note-title")
                    Button(NoteContent.hasContent(draft.content) ? "编辑本次正文" : "编写本次正文") { composerScope = id }
                        .accessibilityIdentifier("trip-note-content")
                    PhotosPicker(selection: $coverPhoto, matching: .images) {
                        MarkerCoverBanner {
                            if let raw = draft.headerImage, let url = imageURL(raw) {
                                AsyncImage(url: url) { phase in
                                    if let image = phase.image { image.resizable().scaledToFill() }
                                    else { Color(uiColor: .secondarySystemBackground) }
                                }
                            } else {
                                Label("添加旅行封面", systemImage: "photo.badge.plus").frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityIdentifier("trip-note-cover")
                    if draft.headerImage?.isEmpty == false {
                        Button("移除旅行封面", role: .destructive) { notes[id]?.headerImage = nil }
                            .accessibilityIdentifier("trip-note-cover-remove")
                    }
                    Button("复制通用攻略到本次正文") { write(copy: true) }
                        .disabled(draft.changed || draft.mustRefresh || NoteContent.hasContent(draft.content))
                    if let error = draft.error { Text(error).foregroundStyle(.red) }
                    if draft.mustRefresh {
                        Button("刷新服务器版本（保留草稿）") { Task { await load(id, preservingDraft: true) } }
                        if draft.hasLatest {
                            Text("服务器标题：" + (draft.latest?.title ?? "无"))
                            if let image = draft.latest?.headerImage, let url = imageURL(image) {
                                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
                            }
                            if let content = draft.latest?.content, NoteContent.hasContent(content) { TripNoteHTML(html: content) }
                            else { Text("无正文").foregroundStyle(.secondary) }
                            Button("已核对，以此版本继续编辑") {
                                notes[id]?.version = draft.latest?.updatedAt
                                notes[id]?.hasLatest = false; notes[id]?.mustRefresh = false; notes[id]?.error = nil
                            }
                        }
                    }
                } else {
                    if let error = loadErrors[id] { Text(error).foregroundStyle(.red) }
                    Button("加载旅行笔记") { Task { await load(id, preservingDraft: false) } }
                }
            }
        }.id(id).disabled(busy || !connectionMatches)
            .onChange(of: coverPhoto) { _, item in
                guard let item else { return }
                let scopeID = id
                busy = true
                Task {
                    defer { busy = false; coverPhoto = nil }
                    do {
                        guard connectionMatches, let bytes = try await item.loadTransferable(type: Data.self) else { throw CancellationError() }
                        let data = try await Task.detached { try MarkerImageCompression.jpeg(from: bytes) }.value
                        guard connectionMatches else { throw CancellationError() }
                        guard !store.demo else { throw AppError.message("只读示例不上传照片") }
                        let url = try await context.client.uploadImage(data)
                        guard connectionMatches else { return }
                        notes[scopeID]?.headerImage = url
                    } catch { notes[scopeID]?.error = error.localizedDescription }
                }
            }
    }
    private func load(_ id: String, preservingDraft: Bool) async {
        guard connectionMatches, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let note = try await store.loadTripNote(tripID: id, markerID: context.marker.id, using: context.client)
            guard connectionMatches else { return }
            if preservingDraft { notes[id]?.latest = note; notes[id]?.hasLatest = true }
            else { notes[id] = TripNoteEditDraft(note: note); loadErrors[id] = nil }
        } catch { loadErrors[id] = error.localizedDescription; notes[id]?.error = error.localizedDescription }
    }
    private func write(copy: Bool) {
        let id = selected
        guard connectionMatches, !working, let draft = notes[id], !draft.mustRefresh else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let note = try await store.writeTripNote(tripID: id, markerID: context.marker.id, title: draft.title,
                    content: draft.content, version: draft.version, copy: copy, headerImage: draft.coverPatch, using: context.client)
                guard connectionMatches else { return }
                notes[id] = TripNoteEditDraft(note: note); status = copy ? "已复制到本次旅行" : "旅行笔记已保存"
            } catch { notes[id]?.error = error.localizedDescription; notes[id]?.mustRefresh = true }
        }
    }
}
