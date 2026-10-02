import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MarkerDetailView: View {
    @ObservedObject var store: AppStore
    let marker: Marker
    var onClose: () -> Void
    var onNavigateItinerary: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationUnavailable = false
    @State private var editing = false
    @State private var deleting = false
    @State private var noteHeight: CGFloat = 1
    private var current: Marker { store.selectedMarker ?? store.markers.first(where: { $0.id == marker.id }) ?? marker }
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
        detailContent
            .alert("无法打开高德地图", isPresented: $navigationUnavailable) {
                Button("取消", role: .cancel) {}
                Button("打开系统地图") { MarkerPresentation.appleMapsItem(for: current)?.openInMaps(launchOptions: nil) }
            } message: { Text("请确认已安装高德地图，或使用系统地图打开此地点。") }
    }
    private var detailContent: some View {
        NavigationStack {
            ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let image = current.content.headerImage, let url = imageURL(image) {
                        MarkerCoverBanner {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Theme.paper.overlay(Image(systemName: "photo").foregroundStyle(.secondary)) }
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    Label(current.title, systemImage: current.icon.symbol).font(.title2.weight(.bold)).foregroundStyle(Theme.ink)
                    if let address = current.content.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                    HStack(spacing: 12) {
                        if let item = MarkerPresentation.appleMapsItem(for: current) {
                            Button {
                                if store.settings.navigationMapApp == .amap,
                                   let url = MarkerPresentation.amapNavigationURL(for: current) {
                                    UIApplication.shared.open(url, options: [:]) { opened in
                                        Task { @MainActor in navigationUnavailable = !opened }
                                    }
                                } else {
                                    item.openInMaps(launchOptions: nil)
                                }
                            } label: {
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
                        HTMLReader(html: current.content.markdownContent, contentHeight: $noteHeight)
                            .frame(height: noteHeight).accessibilityIdentifier("marker-note")
                    }
                }.padding(20)
            }
            .id(current.id)
            .transition(reduceMotion ? .identity : .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .clipped()
            .animation(AppMotion.presentation(reduceMotion: reduceMotion), value: current.id)
            .navigationTitle("地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { onClose() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("关闭")
                            .accessibilityIdentifier("close-marker-detail")
                    }
                    ToolbarItem(placement: .confirmationAction) { Button { editing = true } label: { Image(systemName: "square.and.pencil") }
                        .accessibilityLabel("编辑") }
                }
                .sheet(isPresented: $editing) { MarkerEditorView(store: store, initial: MarkerDraft(marker: current)) }
                .alert("删除地点？", isPresented: $deleting) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) { if store.deleteMarker(current) { dismiss() } }
                } message: { Text("会从所有每日行程和路线中移除这个地点。") }
        }.onChange(of: current.content.markdownContent) { _, _ in noteHeight = 1 }
            .task(id: current.id) { await store.refreshSelectedMarker(current.id) }
            .modifier(MarkerDetailPresentation(compactDetails: compactDetails, compactHeight: compactHeight, restingFraction: detailLayout.restingFraction))
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
    @State private var noteEditorPresented = false
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
                            withTransaction(transaction) {
                                draft.icon = icon
                                if store.draft?.id == initial.id { store.draft?.icon = icon }
                            }
                        } label: { Label(icon.label, systemImage: icon.symbol) }
                            .accessibilityIdentifier("marker-icon-option-\(icon.rawValue)")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: draft.icon.symbol).font(.system(size: 20))
                        Image(systemName: "chevron.down").font(.caption2)
                    }.frame(width: 44, height: 32)
                }.buttonStyle(.borderless).accessibilityLabel("地点类型：\(draft.icon.label)")
                    .accessibilityIdentifier("marker-icon-picker")
                TextField("地点名称", text: $draft.title).font(.body)
            }.transaction { $0.animation = nil }
            if !draft.address.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("地址")
                    Text(draft.address).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
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
            MarkerCoverBanner {
                if uploading {
                    HStack { ProgressView(); Text("上传中…") }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let uploadedPreview {
                    Image(uiImage: uploadedPreview).resizable().scaledToFill()
                } else if let url = imageURL(draft.headerImage) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { Label("更换封面图", systemImage: "photo").frame(maxWidth: .infinity, maxHeight: .infinity) }
                    }
                } else {
                    Label("添加封面图", systemImage: "photo")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .systemBackground))
                }
            }.contentShape(Rectangle())
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
        else { NavigationStack { editorContent }.modifier(IPadMarkerDialogPresentation(allowsBackgroundInteraction: initial.marker == nil)) }
    }
    private var editorContent: some View {
            GeometryReader { geometry in
                Form {
                    Section { editorFields }
                    Section { coverPicker } header: { Text("封面") }
                    Section("地点笔记") {
                        Button { noteEditorPresented = true } label: {
                            Label(NoteContent.hasContent(draft.html) ? "编辑笔记" : "编写笔记", systemImage: "square.and.pencil")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.accessibilityIdentifier("marker-note-editor")
                    }
                    if let localError { Section { Text(localError).foregroundStyle(.red) } }
                }.scrollDismissesKeyboard(.interactively)
            }
                .navigationTitle(embedded || initial.marker == nil ? "添加地点" : "编辑地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            if embedded && hasChanges { confirmDiscard = true }
                            else { closeEditor() }
                        } label: { Image(systemName: "xmark") }
                            .disabled(store.saving || uploading)
                            .accessibilityLabel("取消")
                            .accessibilityIdentifier("cancel-marker-editor")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task {
                            if initial.marker == nil {
                                guard let lat = Double(latitude), let lng = Double(longitude) else { localError = "请输入有效经纬度"; return }
                                draft.coordinates = Coordinate(latitude: lat, longitude: lng)
                            }
                            draft.html = rich.exportHTML(original: draft.html)
                            if embedded, let place = store.searchResults.first(where: { $0.id == store.editingSearchPlaceID }) {
                                if await store.addSearchPlace(place, edited: draft) { onSaved(); closeEditor() }
                                else { localError = store.addPlaceError }
                            } else if await store.saveMarker(draft) { onSaved(); dismiss() }
                            else { localError = store.errorMessage }
                        }} label: { Image(systemName: "checkmark") }
                            .accessibilityLabel("保存")
                            .disabled(store.saving || uploading || draft.title.isEmpty)
                    }
                }
        .fullScreenCover(isPresented: $noteEditorPresented) {
            NoteComposerPreview(placeName: draft.title, address: draft.address,
                initialHTML: draft.html, preview: false,
                uploadPhoto: { data in try await store.api.uploadImage(data) },
                onSave: { html in draft.html = html })
        }
        .navigationBarBackButtonHidden(embedded)
        .confirmationDialog("放弃修改？", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { closeEditor() }
            Button("继续编辑", role: .cancel) {}
        }
        .onDisappear {
            if embedded, store.draft?.id == initial.id {
                draft.html = rich.exportHTML(original: draft.html)
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
        .onChange(of: store.draft?.coordinates) { _, coordinate in
            guard let latest = store.draft, latest.id == initial.id, let coordinate,
                  coordinate != draft.coordinates else { return }
            draft.coordinates = coordinate
            draft.title = latest.title
            draft.address = latest.address
            latitude = String(coordinate.latitude)
            longitude = String(coordinate.longitude)
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
        draft.title != initial.title || draft.icon != initial.icon || draft.headerImage != initial.headerImage || draft.html != initial.html
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
    let restingFraction: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder func body(content: Content) -> some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            content.modifier(IPadMarkerDialogPresentation(allowsBackgroundInteraction: true))
        } else {
            content.background {
                MarkerSheetResize(compact: compactDetails, height: compactHeight, fraction: restingFraction, reduceMotion: reduceMotion)
                    .allowsHitTesting(false)
            }
                .presentationBackgroundInteraction(.enabled)
                .presentationDragIndicator(.visible)
        }
    }
}

/// The cover always fills the available width; source images are cropped, never stretched.
private struct MarkerCoverBanner<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    content().frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity)
            .clipped()
    }
}

/// Keep one stable resting detent and animate its resolver changes with UIKit.
private struct MarkerSheetResize: UIViewRepresentable {
    let compact: Bool
    let height: CGFloat
    let fraction: CGFloat
    let reduceMotion: Bool
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ view: Probe, context: Context) {
        view.compact = compact; view.height = height; view.fraction = fraction; view.reduceMotion = reduceMotion
        view.setNeedsLayout()
    }
    final class Probe: UIView {
        var compact = false
        var height: CGFloat = 0
        var fraction: CGFloat = 0.55
        private var resolvedCompact = false
        private var resolvedHeight: CGFloat = 0
        private var resolvedFraction: CGFloat = 0.55
        var reduceMotion = false
        private var previous: String?
        private weak var configuredSheet: UISheetPresentationController?
        private let resting = UISheetPresentationController.Detent.Identifier("marker-resting")
        override func didMoveToWindow() { super.didMoveToWindow(); setNeedsLayout() }
        override func layoutSubviews() {
            super.layoutSubviews()
            var responder: UIResponder? = self
            var sheet: UISheetPresentationController?
            while let next = responder?.next {
                responder = next
                if let controller = next as? UIViewController,
                   let value = controller.presentationController as? UISheetPresentationController,
                   value.presentedViewController === controller {
                    sheet = value; break
                }
            }
            guard window != nil, let sheet else { return }
            let key = "\(compact):\(height):\(fraction)"
            guard configuredSheet !== sheet || previous != key else { return }
            let first = configuredSheet !== sheet
            configuredSheet = sheet; previous = key
            let updateResolver = {
                self.resolvedCompact = self.compact
                self.resolvedHeight = self.height
                self.resolvedFraction = self.fraction
            }
            if first {
                updateResolver()
                sheet.detents = [.custom(identifier: resting) { [weak self] context in
                    guard let self else { return nil }
                    return self.resolvedCompact ? min(self.resolvedHeight, context.maximumDetentValue) : context.maximumDetentValue * self.resolvedFraction
                }, .large()]
                sheet.selectedDetentIdentifier = resting
                sheet.largestUndimmedDetentIdentifier = resting
            } else {
                let changes = { updateResolver(); sheet.invalidateDetents() }
                if reduceMotion { changes() }
                else { sheet.animateChanges(changes) }
            }
        }
    }
}


/// Native note composer. Sample content is only enabled by the debug preview entry.
struct NoteComposerPreview: View {
    let placeName: String
    let address: String
    var initialHTML = ""
    var preview = true
    var uploadPhoto: ((Data) async throws -> String)?
    var onSave: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var editor = RichEditorController()
    @State private var selection: [PhotosPickerItem] = []
    @State private var photos: [UIImage] = []
    @State private var photoURLs: [String] = []
    @State private var loadingPhotos = false
    @State private var discard = false
    @State private var photoError: String?
    private let sampleHTML = "<p><b>武康路散步记录</b></p><p>午后漫步武康路，在街角喝一杯咖啡。</p><p>• 上午光线柔和，适合拍照<br>• 附近的小店值得慢慢逛</p><p>下次再留一个不赶时间的下午。</p>"

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RichEditor(controller: editor, initialHTML: preview ? sampleHTML : initialHTML)
                    .accessibilityIdentifier("note-composer-text")
                    .padding(.horizontal, 6)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, image in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: 92, height: 92).clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(alignment: .topTrailing) {
                                    Button {
                                        photos.remove(at: index)
                                        if photoURLs.indices.contains(index) { photoURLs.remove(at: index) }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                                            .frame(width: 32, height: 32)
                                    }.accessibilityLabel("移除第\(index + 1)张图片")
                                }
                        }
                        PhotosPicker(selection: $selection, maxSelectionCount: max(1, 9 - photos.count), matching: .images) {
                            Image(systemName: "plus").font(.system(size: 28, weight: .light))
                                .foregroundStyle(.secondary).frame(width: 92, height: 92)
                                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(uiColor: .separator), style: StrokeStyle(lineWidth: 1, dash: [4])))
                        }.disabled(photos.count >= 9 || loadingPhotos).accessibilityLabel("添加图片，可多选")
                    }.padding(.horizontal, 16).padding(.vertical, 12)
                }.scrollIndicators(.hidden)
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(.red).padding(.horizontal, 16) }
                HStack {
                    Label {
                        Text(placeName)
                    } icon: {
                        NoteLocationPin().fill(style: FillStyle(eoFill: true))
                            .frame(width: 14, height: 19)
                    }
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color(uiColor: .secondarySystemBackground), in: CompactCapsuleShape())
                        .accessibilityLabel("当前地点：\(placeName)，\(address)")
                    Spacer()
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 12)
            }
            .background(Color(uiColor: .systemBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    Divider()
                    HStack(spacing: 0) {
                        formatButton("粗体", symbol: "bold") { editor.toggleBold() }
                        formatButton("斜体", symbol: "italic") { editor.toggleItalic() }
                        Menu {
                            Button("标题", systemImage: "textformat.size.larger") { editor.setHeading(true) }
                            Button("正文", systemImage: "textformat") { editor.setHeading(false) }
                        } label: { Image(systemName: "textformat.size").frame(maxWidth: .infinity, minHeight: 48) }
                            .accessibilityLabel("标题与正文")
                        formatButton("下划线", symbol: "underline") { editor.toggleUnderline() }
                        formatButton("项目列表", symbol: "list.bullet") { editor.insertBullet() }
                        formatButton("编号列表", symbol: "list.number") { editor.insertNumberedItem() }
                    }.font(.system(size: 20)).tint(Color(uiColor: .label)).buttonStyle(.plain)
                        .padding(.horizontal, 8)
                }.background(Color(uiColor: .systemBackground))
            }
            .navigationTitle("编写笔记").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { if editor.changed || !photos.isEmpty { discard = true } else { dismiss() } } label: {
                        Image(systemName: "xmark")
                    }.disabled(loadingPhotos).accessibilityLabel("退出笔记编辑")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        var html = editor.exportHTML(original: preview ? sampleHTML : initialHTML)
                        let images = photoURLs.map { "<p><img src=\"\($0.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "\"", with: "&quot;"))\" /></p>" }.joined()
                        if let end = html.range(of: "</body>", options: .caseInsensitive) {
                            html.insert(contentsOf: images, at: end.lowerBound)
                        } else { html += images }
                        onSave?(html)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark").fontWeight(.semibold)
                    }.disabled(loadingPhotos).accessibilityLabel("保存笔记")
                }
            }
            .interactiveDismissDisabled(loadingPhotos)
            .confirmationDialog("放弃修改？", isPresented: $discard) {
                Button("放弃修改", role: .destructive) { dismiss() }
                Button("继续编辑", role: .cancel) {}
            }
            .task {
                if preview { photos = [samplePhoto(alternate: false), samplePhoto(alternate: true)] }
                try? await Task.sleep(for: .milliseconds(400))
                editor.textView?.becomeFirstResponder()
            }
            .onChange(of: selection) { _, items in
                Task {
                    guard !items.isEmpty, !loadingPhotos else { return }
                    loadingPhotos = true
                    defer { loadingPhotos = false; selection = [] }
                    photoError = nil
                    for item in items {
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                let compressed = try await Task.detached(priority: .userInitiated) {
                                    try MarkerImageCompression.jpeg(from: data)
                                }.value
                                if let image = UIImage(data: compressed), photos.count < 9 {
                                    if !preview, let uploadPhoto {
                                        let url = try await uploadPhoto(compressed)
                                        photoURLs.append(url)
                                    }
                                    photos.append(image)
                                }
                            }
                        } catch { photoError = "部分图片未能添加：\(error.localizedDescription)" }
                    }
                    selection = []
                }
            }
        }
    }
    private func formatButton(_ label: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(maxWidth: .infinity, minHeight: 48) }
            .accessibilityLabel(label)
    }
    private func samplePhoto(alternate: Bool) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 240, height: 240)).image { context in
            let cg = context.cgContext
            UIColor(red: 0.80, green: 0.88, blue: 0.91, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: 240, height: 240))
            UIColor(red: 0.82, green: 0.76, blue: 0.65, alpha: 1).setFill()
            cg.fill(CGRect(x: 0, y: 190, width: 240, height: 50))
            for column in 0..<4 {
                let x = CGFloat(column * 60)
                UIColor(red: alternate ? 0.68 : 0.74, green: 0.57, blue: 0.44, alpha: 1).setFill()
                cg.fill(CGRect(x: x + 4, y: 55 + CGFloat(column * 8), width: 54, height: 135))
                UIColor(red: 0.25, green: 0.32, blue: 0.35, alpha: 1).setFill()
                for row in 0..<4 {
                    cg.fill(CGRect(x: x + 13, y: 70 + CGFloat(row * 28 + column * 8), width: 12, height: 18))
                    cg.fill(CGRect(x: x + 37, y: 70 + CGFloat(row * 28 + column * 8), width: 12, height: 18))
                }
            }
            UIColor(red: 0.32, green: 0.47, blue: 0.32, alpha: 1).setFill()
            cg.fillEllipse(in: CGRect(x: alternate ? 145 : -20, y: -25, width: 115, height: 140))
        }
    }
}


private struct NoteLocationPin: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w / 2, y: h))
        path.addCurve(to: CGPoint(x: 0, y: h * 0.37),
                      control1: CGPoint(x: w * 0.38, y: h * 0.83),
                      control2: CGPoint(x: 0, y: h * 0.62))
        path.addCurve(to: CGPoint(x: w / 2, y: 0),
                      control1: CGPoint(x: 0, y: h * 0.16),
                      control2: CGPoint(x: w * 0.22, y: 0))
        path.addCurve(to: CGPoint(x: w, y: h * 0.37),
                      control1: CGPoint(x: w * 0.78, y: 0),
                      control2: CGPoint(x: w, y: h * 0.16))
        path.addCurve(to: CGPoint(x: w / 2, y: h),
                      control1: CGPoint(x: w, y: h * 0.62),
                      control2: CGPoint(x: w * 0.62, y: h * 0.83))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: w * 0.29, y: h * 0.20, width: w * 0.42, height: w * 0.42))
        return path
    }
}
