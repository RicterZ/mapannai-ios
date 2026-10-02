import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MarkerDetailView: View {
    @ObservedObject var store: AppStore
    let marker: Marker
    var onClose: () -> Void
    var onNavigateItinerary: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    private var current: Marker { store.markers.first(where: { $0.id == marker.id }) ?? marker }
    private var hasNote: Bool { NoteContent.hasContent(current.content.markdownContent) }
    private var detailLayout: MarkerDetailLayout {
        MarkerDetailLayout(marker: current, itineraryCount: itineraries.count, hasSelectedDay: store.day != nil)
    }
    private var compactDetails: Bool { detailLayout.compact }
    private var itineraries: [MarkerItinerary] { MarkerPresentation.itineraries(for: current.id, trips: store.trips) }
    private var compactHeight: CGFloat {
        detailLayout.compactHeight
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let image = current.content.headerImage, let url = imageURL(image) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { Theme.paper.overlay(Image(systemName: "photo").foregroundStyle(.secondary)) }
                        }.frame(height: 210).clipped().clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    Label(current.title, systemImage: current.icon.symbol).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    if let address = current.content.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                    HStack(spacing: 12) {
                        if let item = MarkerPresentation.appleMapsItem(for: current) {
                            Button { item.openInMaps(launchOptions: nil) } label: {
                                Label("导航", systemImage: "location")
                                    .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(Theme.accent).background(Theme.consoleRaised, in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).accessibilityIdentifier("marker-navigate")
                        }
                        Button(role: .destructive) { deleting = true } label: {
                            Label("删除", systemImage: "trash")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                                .foregroundStyle(.red).background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).accessibilityIdentifier("marker-delete")
                    }
                    if !itineraries.isEmpty {
                        VStack(spacing: 6) {
                            ForEach(itineraries) { itinerary in
                                Button {
                                    store.select(trip: itinerary.trip, day: itinerary.day, focus: false)
                                    onNavigateItinerary()
                                    dismiss()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: "map").foregroundStyle(Theme.muted)
                                        Text(itinerary.trip.name).lineLimit(1)
                                        Text("· 第\(itinerary.dayNumber)天").foregroundStyle(Theme.muted).fixedSize()
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.muted)
                                    }.font(.subheadline.weight(.medium)).foregroundStyle(Theme.text)
                                        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                        .background(Theme.consoleRaised, in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier("marker-itinerary-\(itinerary.day.id)")
                            }
                        }
                    }
                    if let day = store.day {
                        if day.markerIds.contains(current.id) {
                            Label("在今日行程中", systemImage: "checkmark").font(.subheadline)
                                .foregroundStyle(Theme.accent).frame(maxWidth: .infinity, minHeight: 32)
                                .accessibilityIdentifier("marker-in-current-day")
                        } else {
                            Button {
                                Task { if await store.addMarker(current, to: day) { dismiss() } }
                            } label: {
                                Label("加入今日行程", systemImage: "plus").frame(maxWidth: .infinity, minHeight: 32)
                            }.buttonStyle(.borderedProminent).disabled(store.saving)
                                .accessibilityIdentifier("add-marker-to-current-day")
                        }
                    }
                    if hasNote {
                        HTMLReader(html: current.content.markdownContent)
                            .frame(minHeight: 120).accessibilityIdentifier("marker-note")
                    }
                }.padding(20)
            }.navigationTitle("地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PanelCloseToolbarItem(identifier: "close-marker-detail") { onClose() }
                    ToolbarItem(placement: .confirmationAction) { Button("编辑") { editing = true } }
                }
                .sheet(isPresented: $editing) { MarkerEditorView(store: store, initial: MarkerDraft(marker: current)) }
                .alert("删除地点？", isPresented: $deleting) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) { if store.deleteMarker(current) { dismiss() } }
                } message: { Text("会从所有每日行程和路线中移除这个地点。") }
        }.task(id: current.id) { await store.refreshSelectedMarker(current.id) }
            .modifier(MarkerDetailPresentation(compactDetails: compactDetails, compactHeight: compactHeight))
    }

}
func imageURL(_ raw: String) -> URL? {
    guard var parts = URLComponents(string: raw), parts.scheme == "https" || parts.scheme == "http" else { return nil }
    if parts.host?.contains("myqcloud.com") == true && parts.query == nil { parts.percentEncodedQuery = "imageMogr2/thumbnail/1200x/quality/80" }
    return parts.url
}
struct MarkerEditorView: View {
    @ObservedObject var store: AppStore
    let initial: MarkerDraft
    var onSaved: () -> Void = {}
    var embedded = false
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MarkerDraft
    @StateObject private var rich = RichEditorController()
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadedPreview: UIImage?
    @State private var localError: String?
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var confirmDiscard = false
    init(store: AppStore, initial: MarkerDraft, embedded: Bool = false, onSaved: @escaping () -> Void = {}) {
        self.store = store; self.initial = initial; self.embedded = embedded; self.onSaved = onSaved; _draft = State(initialValue: initial)
    }
    private var editorFields: some View {
        Group {
            HStack(spacing: 12) {
                Menu {
                    ForEach(MarkerIcon.allCases) { icon in
                        Button {
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) { draft.icon = icon }
                        } label: { Label(icon.label, systemImage: icon.symbol) }
                            .accessibilityIdentifier("marker-icon-option-\(icon.rawValue)")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: draft.icon.symbol).font(.system(size: 20))
                        Image(systemName: "chevron.down").font(.caption2)
                    }.frame(width: 44, height: 44)
                }.buttonStyle(.borderless).accessibilityLabel("地点类型：\(draft.icon.label)")
                    .accessibilityIdentifier("marker-icon-picker")
                TextField("地点名称", text: $draft.title).font(.body).frame(minHeight: 44)
            }.transaction { $0.animation = nil }
            if !draft.address.isEmpty { LabeledContent("地址", value: draft.address) }
            if store.draft?.id == initial.id && store.draft?.resolvingPlace == true {
                HStack { ProgressView(); Text("获取地点信息…").foregroundStyle(.secondary) }
            }
            if store.draft?.id == initial.id && store.draft?.placeLookupFailed == true {
                Text("未获取到地点信息，可手动填写。").font(.footnote).foregroundStyle(.secondary)
            }
            if initial.marker == nil {
                DisclosureGroup("标点坐标 · WGS-84") {
                    TextField("纬度", text: $latitude).keyboardType(.numbersAndPunctuation)
                    TextField("经度", text: $longitude).keyboardType(.numbersAndPunctuation)
                }
            }
        }
    }
    private var coverPicker: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            if uploading {
                HStack { ProgressView(); Text("上传中…") }.frame(maxWidth: .infinity, minHeight: 44)
            } else if let uploadedPreview {
                Image(uiImage: uploadedPreview).resizable().scaledToFit().frame(maxWidth: .infinity)
            } else if let url = imageURL(draft.headerImage) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else { Label("更换封面图", systemImage: "photo") }
                }.frame(maxWidth: .infinity)
            } else {
                Label("添加封面图", systemImage: "photo").frame(minHeight: 44)
            }
        }.buttonStyle(.plain)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .disabled(uploading || store.saving)
            .accessibilityLabel(draft.headerImage.isEmpty && uploadedPreview == nil ? "上传封面图" : "重新上传封面图")
            .accessibilityIdentifier("marker-cover-upload")
    }
    private var noteToolbar: some View {
        HStack {
            Text("地点笔记")
            Spacer()
            Button { rich.toggleBold() } label: { Image(systemName: "bold").frame(width: 32, height: 32) }.accessibilityLabel("粗体")
            Button { rich.toggleItalic() } label: { Image(systemName: "italic").frame(width: 32, height: 32) }.accessibilityLabel("斜体")
            Button { rich.insertBullet() } label: { Image(systemName: "list.bullet").frame(width: 32, height: 32) }.accessibilityLabel("列表")
        }.buttonStyle(.borderless).textCase(nil)
    }
    @ViewBuilder var body: some View {
        if embedded { editorContent }
        else { NavigationStack { editorContent }.modifier(IPadMarkerDialogPresentation()) }
    }
    private var editorContent: some View {
            GeometryReader { geometry in
                Form {
                    Section { editorFields }
                    Section { coverPicker } header: { Text("封面") }
                    Section {
                        RichEditor(controller: rich, initialHTML: draft.html)
                            .frame(height: max(160, geometry.size.height - 416))
                            .accessibilityIdentifier("marker-note-editor")
                    } header: { noteToolbar }
                    if let localError { Section { Text(localError).foregroundStyle(.red) } }
                }.scrollDismissesKeyboard(.interactively)
            }
                .navigationTitle(embedded || initial.marker == nil ? "添加地点" : "编辑地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") {
                        if embedded && hasChanges { confirmDiscard = true }
                        else { closeEditor() }
                    }.disabled(store.saving || uploading) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task {
                            if initial.marker == nil {
                                guard let lat = Double(latitude), let lng = Double(longitude) else { localError = "请输入有效经纬度"; return }
                                draft.coordinates = Coordinate(latitude: lat, longitude: lng)
                            }
                            draft.html = rich.exportHTML(original: initial.html)
                            if embedded, let place = store.searchResults.first(where: { $0.id == store.editingSearchPlaceID }) {
                                if await store.addSearchPlace(place, edited: draft) { onSaved(); closeEditor() }
                                else { localError = store.addPlaceError }
                            } else if await store.saveMarker(draft) { onSaved(); dismiss() }
                            else { localError = store.errorMessage }
                        }}.disabled(store.saving || uploading || draft.title.isEmpty)
                    }
                }
        .navigationBarBackButtonHidden(embedded)
        .confirmationDialog("放弃修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { closeEditor() }
            Button("继续编辑", role: .cancel) {}
        }
        .onDisappear {
            if embedded, store.draft?.id == initial.id {
                draft.html = rich.exportHTML(original: initial.html)
                store.draft = draft
            }
        }
        .onAppear {
            latitude = String(draft.coordinates.latitude); longitude = String(draft.coordinates.longitude)
            if let latest = store.draft, latest.id == initial.id {
                if draft.title.isEmpty { draft.title = latest.title }
                if draft.address.isEmpty { draft.address = latest.address }
            }
        }
        .onChange(of: store.draft?.title) { _, value in
            guard store.draft?.id == initial.id, draft.title.isEmpty, let value else { return }
            draft.title = value
        }
        .onChange(of: store.draft?.address) { _, value in
            guard store.draft?.id == initial.id, draft.address.isEmpty, let value else { return }
            draft.address = value
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                uploading = true; localError = nil; defer { uploading = false; photo = nil }
                do {
                    guard let bytes = try await item.loadTransferable(type: Data.self) else { throw AppError.message("无法读取图片") }
                    let data = try await Task.detached(priority: .userInitiated) {
                        try MarkerImageCompression.jpeg(from: bytes)
                    }.value
                    if store.demo {
                        uploadedPreview = UIImage(data: data)
                    } else {
                        let url = try await store.api.uploadImage(data)
                        draft.headerImage = url
                        uploadedPreview = UIImage(data: data)
                    }
                } catch { localError = error.localizedDescription }
            }
        }.interactiveDismissDisabled(store.saving || uploading)
    }
    private var hasChanges: Bool {
        draft.title != initial.title || draft.icon != initial.icon || draft.headerImage != initial.headerImage
            || rich.changed || latitude != String(initial.coordinates.latitude) || longitude != String(initial.coordinates.longitude)
    }
    private func closeEditor() {
        if embedded { store.draft = nil; store.editingSearchPlaceID = nil }
        else { dismiss() }
    }
}

private struct IPadMarkerDialogPresentation: ViewModifier {
    var allowsBackgroundInteraction = false
    @ViewBuilder func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 18.0, *) {
                content.presentationSizing(.form)
                    .presentationDragIndicator(.hidden)
                    .presentationBackgroundInteraction(allowsBackgroundInteraction ? .enabled : .disabled)
                    .interactiveDismissDisabled()
            } else {
                // Without detents, iOS 17 uses its centered iPad form presentation.
                content.presentationDragIndicator(.hidden)
                    .presentationBackgroundInteraction(allowsBackgroundInteraction ? .enabled : .disabled)
                    .interactiveDismissDisabled()
            }
        } else {
            content
        }
    }
}

private struct MarkerDetailPresentation: ViewModifier {
    let compactDetails: Bool
    let compactHeight: CGFloat
    @ViewBuilder func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.modifier(IPadMarkerDialogPresentation(allowsBackgroundInteraction: true))
        } else {
            content.presentationDetents(compactDetails ? [.height(compactHeight), .large] : [.medium, .large])
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
    }
}
