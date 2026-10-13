import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MarkerDetailView: View {
    @ObservedObject var store: AppStore
    let marker: Marker
    var edgeAttached = false
    var embedded = false
    var compact = false
    var onExpand: () -> Void = {}
    var searchPlace: Place?
    var onClose: () -> Void
    var onNavigateItinerary: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationUnavailable = false
    @State private var editing = false
    @State private var deleting = false
    @State private var removingFromDay = false
    @State private var removalTarget: (day: TripDay, markerID: String)?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var noteHeight: CGFloat = 1
    @ScaledMetric(relativeTo: .title3) private var identityIconSize: CGFloat = 48
    private var current: Marker {
        (!embedded ? store.selectedMarker : nil) ?? store.markers.first(where: { $0.id == marker.id }) ?? marker
    }
    private var targetDay: TripDay? {
        guard embedded else { return store.day }
        guard let target = store.addPlaceDay else { return nil }
        return store.trips.first(where: { $0.id == target.tripId })?.days.first(where: { $0.id == target.id })
    }
    private var hasNote: Bool { NoteContent.hasContent(current.content.markdownContent) }
    private var itineraries: [MarkerItinerary] { MarkerPresentation.itineraries(for: current.id, trips: store.trips) }
    var body: some View {
        detailContent
            .appAlert(isPresented: $navigationUnavailable, title: "无法打开高德地图", symbol: "map", message: "请确认已安装高德地图。也可以使用系统地图打开此地点。", actions: [
                AppAlertAction(title: "取消") { navigationUnavailable = false },
                AppAlertAction(title: "系统地图") {
                    navigationUnavailable = false
                    Task { await MarkerPresentation.openAppleMaps(for: current, selectedItem: store.appleMapItem(for: current)) }
                }
            ])
    }
    private var detailContent: some View {
        Group {
            if embedded { detailPage }
            else { NavigationStack { detailPage } }
        }
            .opacity(compact ? 0 : 1)
            .allowsHitTesting(!compact)
            .accessibilityHidden(compact)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay {
                if compact {
                    compactContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .onChange(of: current.content.markdownContent) { _, _ in noteHeight = 1 }
            .task(id: current.id) { await store.refreshSelectedMarker(current.id) }
            .modifier(MarkerDetailPresentation(edgeAttached: edgeAttached, embedded: embedded, onClose: onClose))
    }
    private var compactContent: some View {
                    Button(action: onExpand) {
                        HStack(spacing: 11) {
                            PlaceIconView(emoji: current.icon.emoji, size: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(current.title).font(.body.weight(.semibold)).lineLimit(1)
                                if let address = current.content.address?.trimmingCharacters(in: .whitespacesAndNewlines), !address.isEmpty {
                                    Text(address).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.up").font(.subheadline).foregroundStyle(.secondary)
                                .frame(width: 44, height: 44)
                        }.padding(.horizontal, 20).frame(height: 66)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.primary)
                        .accessibilityLabel("展开地点详情").accessibilityIdentifier("marker-compact-expand")
    }

    private var detailPage: some View {
            detailScroll
            .toolbar(.hidden, for: .navigationBar)

                .sheet(isPresented: Binding(get: { editing && !embedded }, set: { editing = $0 })) {
                    MarkerEditorView(store: store, initial: MarkerDraft(marker: current))
                }
                .navigationDestination(isPresented: Binding(get: { editing && embedded }, set: { editing = $0 })) {
                    MarkerEditorView(store: store, initial: MarkerDraft(marker: current),
                        embedded: true, onSaved: { editing = false }, onClosed: { editing = false })
                        .toolbar(.visible, for: .navigationBar)
                }
                .sheet(isPresented: $removingFromDay, onDismiss: { removalTarget = nil }) {
                    if let target = removalTarget {
                        DeletionConfirmationView(store: store, title: "从今日行程移除", message: "仅从当前日期和当天所有路线中移除，地点收藏及其他日期的安排会保留。", kind: "marker-from-day", offersExclusiveMarkers: false, allowsQueuedWrites: true) { _ in
                            if store.removeDayPlacesInBackground([target.markerID], from: target.day) { onClose() }
                            removalTarget = nil
                        }
                    }
                }
                .sheet(isPresented: $deleting) {
                    let target = current
                    DeletionConfirmationView(store: store, title: "删除地点", message: "删除收藏，并从所有每日行程和路线中移除这个地点。", kind: "marker", offersExclusiveMarkers: false) { _ in
                        if store.deleteMarker(target) { onClose() }
                    }
                }
    }

    private var detailScroll: some View {
            ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 10) {
                        PlaceIconView(emoji: current.icon.emoji, size: identityIconSize)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(current.title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let address = current.content.address, !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text(address).font(.subheadline).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        Button { onClose() } label: {
                            Image(systemName: "xmark").font(.system(size: 20, weight: .regular)).frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).foregroundStyle(.primary)
                            .accessibilityLabel("关闭地点详情").accessibilityIdentifier(embedded ? "search-detail-back" : "close-marker-detail")
                    }
                    if let image = current.content.headerImage, let url = imageURL(image) {
                        MarkerCoverBanner {
                            AsyncImage(url: url) { phase in
                                if let image = phase.image { image.resizable().scaledToFill() }
                                else { Theme.paper.overlay(Image(systemName: "photo").foregroundStyle(.secondary)) }
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 8))
                            .allowsHitTesting(false)
                    }
                    actionBar
                    if !itineraries.isEmpty || hasNote {
                        Divider().padding(.vertical, 4)
                    }
                    if !itineraries.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            JourneyEditorHeading(title: "已包含在如下行程中")
                                .accessibilityIdentifier("marker-itineraries-heading")
                            ForEach(itineraries) { itinerary in
                                Button {
                                    store.select(trip: itinerary.trip, day: itinerary.day, focus: false)
                                    onNavigateItinerary()
                                    onClose()
                                } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                                Text(itinerary.trip.name).lineLimit(1)
                                                if targetDay?.id == itinerary.day.id && targetDay?.tripId == itinerary.trip.id {
                                                    Text("（当前行程）").font(.caption).foregroundStyle(.secondary)
                                                        .fixedSize()
                                                        .accessibilityIdentifier("marker-in-current-day")
                                                }
                                            }
                                            Text("第\(itinerary.dayNumber)天 · " + itinerary.day.date.replacingOccurrences(of: "-", with: "/"))
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Theme.muted)
                                    }.font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).accessibilityIdentifier("marker-itinerary-\(itinerary.day.id)")
                            }
                        }
                    }
                    if hasNote {
                        if !itineraries.isEmpty { Divider().padding(.vertical, 4) }
                        JourneyEditorHeading(title: "笔记")
                        HTMLReader(html: current.content.markdownContent, contentHeight: $noteHeight)
                            .frame(height: noteHeight).accessibilityIdentifier("marker-note")
                    }
                }.padding(24)
            }
            .id(current.id)
            .transition(reduceMotion ? .identity : .opacity)
            }
            .clipped()
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: current.id)
            .accessibilityIdentifier("marker-detail-content")
            .ignoresSafeArea(.container, edges: .top)
    }

    private var markerActionLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
    }

    private var actionBar: some View {

                VStack(alignment: .leading, spacing: 10) {
                    if let searchPlace, !store.isPlaceAdded(searchPlace) {
                        markerActionLayout {
                            Button { store.prepareSearchPlaceAddition(searchPlace) } label: {
                                Label(targetDay.map(addDayLabel) ?? (store.addPlaceTripID != nil ? "加入旅行" : "保存地点"), systemImage: "plus")
                            }.disabled(store.saving).accessibilityIdentifier("search-detail-add")
                        }
                    } else if searchPlace == nil, let day = targetDay, !day.markerIds.contains(current.id) {
                        markerActionLayout {
                            Button {
                                if store.addMarkerInBackground(current, to: day) { onClose() }
                            } label: { Label(addDayLabel(day), systemImage: "plus") }
                                .disabled(store.saving).accessibilityIdentifier("add-marker-to-current-day")
                        }
                    }
                    markerActionLayout {
                        Button(action: navigate) { Label("导航", systemImage: "location").font(.subheadline).frame(minHeight: 44) }
                            .accessibilityIdentifier("marker-navigate").disabled(!current.coordinates.isValid)
                        Button { editing = true } label: { Label("编辑", systemImage: "square.and.pencil").font(.subheadline).frame(minHeight: 44) }
                            .accessibilityIdentifier("edit-marker-detail")
                        if let day = targetDay, day.markerIds.contains(current.id) {
                            Button {
                                removalTarget = (day, current.id); removingFromDay = true
                            } label: { Label("从今日移除", systemImage: "calendar.badge.minus").font(.subheadline).frame(minHeight: 44) }
                                .disabled(store.saving).accessibilityIdentifier("remove-marker-from-current-day")
                        }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Button(role: .destructive) { deleting = true } label: {
                            Label("删除", systemImage: "trash").font(.subheadline).foregroundStyle(.red).frame(minHeight: 44)
                        }.accessibilityLabel("删除地点").accessibilityIdentifier("marker-delete")
                    }
                }.buttonStyle(.plain).font(.subheadline)
                    .padding(.top, 4).padding(.bottom, 6)
                }

    private func addDayLabel(_ day: TripDay) -> String {
        let days = store.trips.first(where: { $0.id == day.tripId })?.days.sorted {
            $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date
        } ?? []
        let number = (days.firstIndex(where: { $0.id == day.id }) ?? 0) + 1
        return "加入第\(number)天 · " + day.date.replacingOccurrences(of: "-", with: "/")
    }

    private func navigate() {
        if store.settings.navigationMapApp == .amap, let url = MarkerPresentation.amapNavigationURL(for: current) {
            UIApplication.shared.open(url, options: [:]) { opened in
                Task { @MainActor in navigationUnavailable = !opened }
            }
        } else if store.settings.navigationMapApp == .google, let url = MarkerPresentation.googleNavigationURL(for: current) {
            UIApplication.shared.open(url)
        } else {
            Task { await MarkerPresentation.openAppleMaps(for: current, selectedItem: store.appleMapItem(for: current)) }
        }
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
    var onClosed: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var draft: MarkerDraft
    @StateObject private var rich = RichEditorController()
    @State private var photo: PhotosPickerItem?
    @State private var uploading = false
    @State private var uploadedPreview: UIImage?
    @State private var localError: String?
    @State private var noteEditorPresented = false
    @State private var confirmDiscard = false
    @State private var iconPickerVisible = false
    @FocusState private var fieldsFocused: Bool
    init(store: AppStore, initial: MarkerDraft, embedded: Bool = false, onSaved: @escaping () -> Void = {}, onClosed: @escaping () -> Void = {}) {
        self.store = store; self.initial = initial; self.embedded = embedded; self.onSaved = onSaved; self.onClosed = onClosed; _draft = State(initialValue: initial)
    }
    private var editorFields: some View {
        Group {
            HStack(spacing: 12) {
                Button { fieldsFocused = false; iconPickerVisible = true } label: {
                    HStack(spacing: 5) {
                        PlaceIconView(emoji: draft.icon.emoji, size: 28)
                        Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }.frame(minWidth: 44, minHeight: 44)
                }.buttonStyle(.plain).accessibilityLabel("地点类型：\(draft.icon.label)")
                    .accessibilityIdentifier("marker-icon-picker")
                    .popover(isPresented: $iconPickerVisible, arrowEdge: .top) {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) {
                            ForEach(MarkerIcon.allCases) { icon in
                                Button {
                                    draft.icon = icon; iconPickerVisible = false
                                    if store.draft?.id == initial.id { store.draft?.icon = icon }
                                } label: {
                                    VStack(spacing: 8) {
                                        PlaceIconView(emoji: icon.emoji, size: 26)
                                        Text(icon.label).font(.caption2)
                                    }.foregroundStyle(.primary).frame(maxWidth: .infinity, minHeight: 64)
                                        .background(draft.icon == icon ? Color(uiColor: .quaternarySystemFill) : .clear,
                                            in: RoundedRectangle(cornerRadius: 12))
                                }.buttonStyle(.plain).accessibilityIdentifier("marker-icon-option-\(icon.rawValue)")
                                    .accessibilityAddTraits(draft.icon == icon ? .isSelected : [])
                            }
                        }.padding(12).frame(width: 320)
                            .presentationBackground(Color(uiColor: .systemBackground))
                            .presentationCompactAdaptation(.popover)
                    }
                TextField("地点名称", text: $draft.title).font(.system(size: 20, weight: .medium))
                    .focused($fieldsFocused).submitLabel(.done).onSubmit { fieldsFocused = false }
                    .accessibilityIdentifier("marker-name-field")
            }.transaction { $0.animation = nil }
            if store.draft?.id == initial.id && store.draft?.resolvingPlace == true {
                HStack { ProgressView(); Text("获取地点信息…").foregroundStyle(.secondary) }
            }
            if store.draft?.id == initial.id && store.draft?.placeLookupFailed == true {
                Text("未获取到地点信息，可手动填写。").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
    private var locationFields: some View {
        Text(draft.address).font(.body).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
    private var coverPicker: some View {
        PhotosPicker(selection: $photo, matching: .images) {
            MarkerCoverBanner {
                if uploading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在保存照片").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(uiColor: .secondarySystemGroupedBackground))
                } else if let uploadedPreview {
                    Image(uiImage: uploadedPreview).resizable().scaledToFill()
                } else if let url = imageURL(draft.headerImage) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                        else { coverPlaceholder(replacing: true) }
                    }
                } else {
                    coverPlaceholder(replacing: false)
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
    private func coverPlaceholder(replacing: Bool) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Color(uiColor: .secondaryLabel).opacity(0.7))
            VStack(spacing: 5) {
                Text(replacing ? "更换封面照片" : "选一张封面照片")
                    .font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                Text("从相册中选择").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
    }
    var body: some View {
        Group {
            if embedded { editorContent }
            else { NavigationStack { editorContent }.modifier(IPadMarkerDialogPresentation(allowsBackgroundInteraction: initial.marker == nil)) }
        }.tint(Color(uiColor: .label))
    }
    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 14) {
                    JourneyEditorHeading(title: "地点名称")
                    VStack(alignment: .leading, spacing: 12) { editorFields }
                        .padding(.vertical, 8)
                    Divider()
                }
                if !draft.address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        JourneyEditorHeading(title: "位置")
                        locationFields
                    }
                }
                VStack(alignment: .leading, spacing: 14) {
                    JourneyEditorHeading(title: "封面")
                    coverPicker.clipShape(RoundedRectangle(cornerRadius: 8))
                }
                VStack(alignment: .leading, spacing: 14) {
                    JourneyEditorHeading(title: "地点笔记")
                    Button { fieldsFocused = false; noteEditorPresented = true } label: {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(NoteContent.hasContent(draft.html) ? "编辑笔记" : "编写笔记")
                                        .font(.body.weight(.medium))
                                    Text(NoteContent.hasContent(draft.html) ? "继续整理这个地点的记录" : "记录预约、攻略和旅行见闻")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical, 8).contentShape(Rectangle()).foregroundStyle(.primary)
                    }.buttonStyle(.plain).accessibilityIdentifier("marker-note-editor")
                }
                if let localError { Text(localError).foregroundStyle(.red).font(.footnote) }
            }.padding(.horizontal, 20).padding(.vertical, 24)
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("marker-editor-scroll")
        .scrollDismissesKeyboard(.interactively)
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            JourneyEditorSubmit(title: initial.marker == nil ? "添加地点" : "保存地点",
                enabled: !store.saving && !uploading && !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                identifier: "save-marker-editor", background: Color(uiColor: .systemBackground), action: save)
        }
        .navigationTitle(initial.marker == nil ? "添加地点" : "编辑地点").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    if embedded && hasChanges { confirmDiscard = true }
                    else { closeEditor() }
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(uiColor: .label))
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .disabled(store.saving || uploading).accessibilityLabel("取消")
                    .accessibilityIdentifier("cancel-marker-editor")
            }.journeyBareBackground
        }
        .fullScreenCover(isPresented: $noteEditorPresented) {
            NoteComposerPreview(placeName: draft.title, address: draft.address,
                initialHTML: draft.html, preview: false,
                uploadPhoto: { data in try await store.api.uploadImage(data) },
                onSave: { html in draft.html = html })
        }
        .navigationBarBackButtonHidden(embedded)
        .appAlert(isPresented: $confirmDiscard, title: "放弃这次修改？", symbol: "square.and.pencil", message: "尚未保存的内容将被丢弃。已保存的地点和行程不会改变。", actions: [
            AppAlertAction(title: "继续编辑") { confirmDiscard = false },
            AppAlertAction(title: "放弃修改", destructive: true) { confirmDiscard = false; closeEditor() }
        ])
        .onDisappear {
            if embedded, store.draft?.id == initial.id {
                draft.html = rich.exportHTML(original: draft.html)
                store.draft = draft
            }
        }
        .onAppear {
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
    private func save() {
        fieldsFocused = false
        draft.html = rich.exportHTML(original: draft.html)
        if embedded, let place = store.searchResults.first(where: { $0.id == store.editingSearchPlaceID }) {
            if store.addSearchPlaceInBackground(place, edited: draft) { onSaved(); closeEditor(restoringMap: false) }
            else { localError = store.addPlaceError ?? store.errorMessage }
        } else if store.saveMarkerInBackground(draft) { onSaved(); if embedded { closeEditor(restoringMap: false) } else { dismiss() } }
        else { localError = store.errorMessage }
    }
    private var hasChanges: Bool {
        draft.title != initial.title || draft.icon != initial.icon || draft.headerImage != initial.headerImage || draft.html != initial.html
            || rich.changed || draft.coordinates != initial.coordinates
    }
    private func closeEditor(restoringMap: Bool = true) {
        if embedded { store.closeSearchDraft(restoringMap: restoringMap); onClosed() }
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
    let edgeAttached: Bool
    var embedded = false
    let onClose: () -> Void
    @State private var detent: PresentationDetent = .medium
    @ViewBuilder func body(content: Content) -> some View {
        if embedded { content.background(Color(uiColor: .systemBackground)) }
        else if UIDevice.current.userInterfaceIdiom == .pad {
            content.modifier(IPadMarkerDialogPresentation(allowsBackgroundInteraction: true))
        } else if edgeAttached { content.background(Color(uiColor: .systemBackground)) }
        else {
            content.presentationDetents([.height(80), .medium, .large], selection: $detent)
                .presentationBackgroundInteraction(.enabled)
                .presentationBackground(Color(uiColor: .systemBackground))
                .presentationDragIndicator(.visible)
                .onChange(of: detent) { _, value in if value == .height(80) { onClose() } }
        }
    }
}

/// The cover always fills the available width; source images are cropped, never stretched.
struct MarkerCoverBanner<Content: View>: View {
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
                    .padding(.horizontal, 14)
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
                        .padding(.vertical, 7)
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
            .appAlert(isPresented: $discard, title: "放弃这次修改？", symbol: "square.and.pencil", message: "尚未保存的笔记将被丢弃。已保存的内容不会改变。", actions: [
                AppAlertAction(title: "继续编辑") { discard = false },
                AppAlertAction(title: "放弃修改", destructive: true) { discard = false; dismiss() }
            ])
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
