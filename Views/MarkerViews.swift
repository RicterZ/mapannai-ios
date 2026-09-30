import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MarkerDetailView: View {
    @ObservedObject var store: AppStore
    let marker: Marker
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var deleting = false
    @State private var adding = false
    private var current: Marker { store.markers.first(where: { $0.id == marker.id }) ?? marker }
    private var hasNote: Bool { NoteContent.hasContent(current.content.markdownContent) }
    private var compactDetails: Bool { !hasNote && imageURL(current.content.headerImage ?? "") == nil }
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
                    if hasNote {
                        HTMLReader(html: current.content.markdownContent).frame(minHeight: 120)
                            .accessibilityIdentifier("marker-note")
                    }
                    Text("\(current.coordinates.latitude.formatted(.number.precision(.fractionLength(6)))), \(current.coordinates.longitude.formatted(.number.precision(.fractionLength(6)))) · WGS-84")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let day = store.day {
                        Button {
                            Task { if await store.addMarker(current, to: day) { dismiss() } }
                        } label: {
                            Label(day.markerIds.contains(current.id) ? "已加入当天" : "加入当天", systemImage: day.markerIds.contains(current.id) ? "checkmark" : "plus")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.borderedProminent).disabled(store.saving || day.markerIds.contains(current.id))
                            .accessibilityIdentifier("add-marker-to-current-day")
                    } else {
                        Button { adding = true } label: { Label("加入每日行程", systemImage: "calendar.badge.plus").frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                    }
                    if let navigation = navigationURL(current) {
                        Link(destination: navigation) { Label("在高德中查看", systemImage: "arrow.up.right.square").frame(maxWidth: .infinity) }.buttonStyle(.bordered)
                    }
                    Button("删除", role: .destructive) { deleting = true }.frame(maxWidth: .infinity, minHeight: 44)
                }.padding(20)
            }.navigationTitle("地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    PanelCloseToolbarItem(identifier: "close-marker-detail") { dismiss() }
                    ToolbarItem(placement: .confirmationAction) { Button("编辑") { editing = true } }
                }
                .sheet(isPresented: $editing) { MarkerEditorView(store: store, initial: MarkerDraft(marker: current)) }
                .sheet(isPresented: $adding) {
                    NavigationStack {
                        List {
                            ForEach(store.trips) { trip in
                                Section(trip.name) {
                                    ForEach(trip.days) { day in
                                        Button { Task { await store.addMarker(current, to: day) } } label: {
                                            HStack {
                                                Text(day.label)
                                                Spacer()
                                                if day.markerIds.contains(marker.id) { Image(systemName: "checkmark.circle.fill") }
                                            }
                                        }.disabled(day.markerIds.contains(marker.id) || store.saving)
                                    }
                                }
                            }
                            if store.trips.isEmpty { Text("先在旅行中创建一次旅行。") }
                        }.navigationTitle("选择日期").navigationBarTitleDisplayMode(.inline)
                            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { adding = false } } }
                    }
                }
                .alert("删除地点？", isPresented: $deleting) {
                    Button("取消", role: .cancel) {}
                    Button("删除", role: .destructive) { Task { await store.deleteMarker(current); if store.selectedMarker == nil { dismiss() } } }
                } message: { Text("会从所有每日行程和路线中移除这个地点。") }
        }.task(id: current.id) { await store.refreshSelectedMarker(current.id) }
            .presentationDetents(compactDetails ? [.height(380), .large] : [.medium, .large])
            .presentationBackgroundInteraction(.enabled)
            .presentationDragIndicator(.visible)
    }
    private func navigationURL(_ marker: Marker) -> URL? {
        let gcj = Coordinates.gcj(marker.coordinates)
        var parts = URLComponents(string: "https://uri.amap.com/marker")!
        parts.queryItems = [URLQueryItem(name: "position", value: "\(gcj.longitude),\(gcj.latitude)"), URLQueryItem(name: "name", value: marker.title), URLQueryItem(name: "coordinate", value: "gaode")]
        return parts.url
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
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MarkerDraft
    @StateObject private var rich = RichEditorController()
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadedPreview: UIImage?
    @State private var localError: String?
    @State private var latitude = ""
    @State private var longitude = ""
    init(store: AppStore, initial: MarkerDraft) {
        self.store = store; self.initial = initial; _draft = State(initialValue: initial)
    }
    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Menu {
                    ForEach(MarkerIcon.allCases) { icon in
                        Button {
                            var transaction = Transaction(); transaction.disablesAnimations = true
                            withTransaction(transaction) { draft.icon = icon }
                        } label: {
                            Label(icon.label, systemImage: icon.symbol)
                        }.accessibilityIdentifier("marker-icon-option-\(icon.rawValue)")
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: draft.icon.symbol)
                            .font(.system(size: 21, weight: .medium)).foregroundStyle(Theme.accent)
                            .frame(width: 28, height: 28)
                        Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.muted)
                    }.frame(width: 56, height: 48)
                        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain).accessibilityLabel("地点类型：\(draft.icon.label)")
                    .accessibilityIdentifier("marker-icon-picker")
                TextField("地点名称", text: $draft.title)
                    .font(.title3.weight(.semibold)).padding(.horizontal, 14).frame(height: 48)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
            }.transaction { $0.animation = nil }
            if store.draft?.id == initial.id && store.draft?.resolvingPlace == true {
                HStack { ProgressView(); Text("获取地点信息…").font(.caption).foregroundStyle(.secondary) }
            }
            if store.draft?.id == initial.id && store.draft?.placeLookupFailed == true {
                Text("未获取到地点信息，可手动填写。").font(.caption).foregroundStyle(.secondary)
            }
            if !draft.address.isEmpty { Text(draft.address).font(.caption).foregroundStyle(.secondary) }
            if initial.marker == nil {
                DisclosureGroup("标点坐标 · WGS-84") {
                    HStack {
                        TextField("纬度", text: $latitude).keyboardType(.numbersAndPunctuation)
                        TextField("经度", text: $longitude).keyboardType(.numbersAndPunctuation)
                    }.textFieldStyle(.roundedBorder).padding(.vertical, 8)
                }.font(.caption)
            }
            PhotosPicker(selection: $photo, matching: .images) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Theme.paper)
                    if let uploadedPreview {
                        Image(uiImage: uploadedPreview).resizable().scaledToFill()
                    } else if let url = imageURL(draft.headerImage) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() }
                            else { coverPlaceholder }
                        }
                    } else { coverPlaceholder }
                    if uploading {
                        Theme.paper.opacity(0.85)
                        ProgressView().tint(Theme.accent)
                    }
                }.frame(maxWidth: .infinity).frame(height: 110).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.muted.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
            }.buttonStyle(.plain).disabled(uploading || store.saving)
                .accessibilityLabel(draft.headerImage.isEmpty && uploadedPreview == nil ? "上传封面图" : "重新上传封面图")
                .accessibilityIdentifier("marker-cover-upload")
            if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
        }
    }
    private var coverPlaceholder: some View {
        Label("点击上传封面图", systemImage: "photo")
            .font(.subheadline).foregroundStyle(Theme.muted)
    }
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let headerHeight = min((draft.address.isEmpty ? 172.0 : 210.0) + (initial.marker == nil ? 50 : 0) + (localError == nil ? 0 : 48) + (draft.resolvingPlace || draft.placeLookupFailed ? 40 : 0), max(0, geometry.size.height - 160))
                VStack(alignment: .leading, spacing: 16) {
                    ScrollView {
                        editorHeader
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(height: headerHeight)
                        .scrollDismissesKeyboard(.interactively)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 14) {
                            Text("地点笔记").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            Button { rich.toggleBold() } label: { Image(systemName: "bold").frame(width: 32, height: 32) }.accessibilityLabel("粗体")
                            Button { rich.toggleItalic() } label: { Image(systemName: "italic").frame(width: 32, height: 32) }.accessibilityLabel("斜体")
                            Button { rich.insertBullet() } label: { Image(systemName: "list.bullet").frame(width: 32, height: 32) }.accessibilityLabel("列表")
                        }
                        RichEditor(controller: rich, initialHTML: draft.html)
                            .frame(height: max(0, geometry.size.height - headerHeight - 96))
                            .frame(maxWidth: .infinity)
                            .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("marker-note-editor")
                    }.frame(maxHeight: .infinity)
                }.padding(20).frame(width: geometry.size.width, height: geometry.size.height).clipped()
            }
                .navigationTitle(initial.marker == nil ? "添加地点" : "编辑地点").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() }.disabled(store.saving || uploading) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") { Task {
                            if initial.marker == nil {
                                guard let lat = Double(latitude), let lng = Double(longitude) else { localError = "请输入有效经纬度"; return }
                                draft.coordinates = Coordinate(latitude: lat, longitude: lng)
                            }
                            draft.html = rich.exportHTML(original: initial.html)
                            if await store.saveMarker(draft) { dismiss() } else { localError = store.errorMessage }
                        }}.disabled(store.saving || uploading || draft.title.isEmpty)
                    }
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
}
