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
        }.presentationDetents(compactDetails ? [.height(380), .large] : [.medium, .large])
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
    @State private var localError: String?
    @State private var latitude = ""
    @State private var longitude = ""
    init(store: AppStore, initial: MarkerDraft) {
        self.store = store; self.initial = initial; _draft = State(initialValue: initial)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    TextField("地点名称", text: $draft.title).font(.title3.weight(.semibold)).padding(14).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                    if store.draft?.id == initial.id && store.draft?.resolvingPlace == true {
                        HStack { ProgressView(); Text("获取地点信息…").font(.caption).foregroundStyle(.secondary) }
                    }
                    if store.draft?.id == initial.id && store.draft?.placeLookupFailed == true {
                        Text("未获取到地点信息，可手动填写。").font(.caption).foregroundStyle(.secondary)
                    }
                    if !draft.address.isEmpty { Text(draft.address).font(.caption).foregroundStyle(.secondary) }
                    Picker("地点类型", selection: $draft.icon) {
                        ForEach(MarkerIcon.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }.pickerStyle(.menu)
                    if initial.marker == nil {
                        DisclosureGroup("标点坐标 · WGS-84") {
                            HStack {
                                TextField("纬度", text: $latitude).keyboardType(.numbersAndPunctuation)
                                TextField("经度", text: $longitude).keyboardType(.numbersAndPunctuation)
                            }.textFieldStyle(.roundedBorder).padding(.vertical, 8)
                        }.font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 18) {
                            Text("地点笔记").font(.subheadline.weight(.semibold))
                            Spacer()
                            Button { rich.toggleBold() } label: { Image(systemName: "bold").frame(width: 32, height: 32) }.accessibilityLabel("粗体")
                            Button { rich.toggleItalic() } label: { Image(systemName: "italic").frame(width: 32, height: 32) }.accessibilityLabel("斜体")
                            Button { rich.insertBullet() } label: { Image(systemName: "list.bullet").frame(width: 32, height: 32) }.accessibilityLabel("列表")
                        }
                        RichEditor(controller: rich, initialHTML: draft.html).frame(height: 240).background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
                    }
                    TextField("首图 URL（可选）", text: $draft.headerImage).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack { Label("上传首图", systemImage: "photo.badge.plus"); if uploading { ProgressView() } }
                    }.disabled(uploading || store.demo)
                    Text("图片直传到已配置的 COS。已有笔记保留 HTML 格式，支持原生文本编辑、粗体、斜体及列表。")
                        .font(.caption2).foregroundStyle(.secondary)
                    if let localError { Text(localError).font(.caption).foregroundStyle(.red) }
                }.padding(20)
            }.scrollDismissesKeyboard(.interactively)
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
                uploading = true; localError = nil; defer { uploading = false }
                do {
                    guard let bytes = try await item.loadTransferable(type: Data.self), let image = UIImage(data: bytes) else { throw AppError.message("无法读取图片") }
                    let size = image.size, scale = min(1, 1600/max(size.width, size.height))
                    let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width*scale, height: size.height*scale))
                    let reduced = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: CGSize(width: size.width*scale, height: size.height*scale))) }
                    guard let data = reduced.jpegData(compressionQuality: 0.82) else { throw AppError.message("无法编码图片") }
                    draft.headerImage = try await store.api.uploadImage(data)
                } catch { localError = error.localizedDescription }
            }
        }.interactiveDismissDisabled(store.saving || uploading)
    }
}
