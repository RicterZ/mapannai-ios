import SwiftUI

struct TripDeletionView: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DeletionConfirmationView(store: store, title: "删除旅途", message: "“\(trip.name)”及其每日行程将被删除。", kind: "trip") { includeMarkers in
            store.deleteItinerary(tripID: trip.id, deleteExclusiveMarkers: includeMarkers, animated: !reduceMotion)
        }
    }
}

struct DayDeletionView: View {
    @ObservedObject var store: AppStore
    let day: TripDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DeletionConfirmationView(store: store, title: "删除当天", message: "\(day.date) 的安排将被删除，后续日期依次前移。", kind: "day") { includeMarkers in
            store.deleteItinerary(tripID: day.tripId, dayID: day.id, deleteExclusiveMarkers: includeMarkers, animated: !reduceMotion)
        }
    }
}

private struct DeletionConfirmationView: View {
    @ObservedObject var store: AppStore
    let title: String
    let message: String
    let kind: String
    let action: (Bool) -> Void
    @State private var contentHeight: CGFloat = 220
    @State private var bottomSafeArea: CGFloat = 0
    @Environment(\.dismiss) private var dismiss
    @State private var deleteExclusiveMarkers = false
    @State private var deleting = false

    var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "trash").font(.subheadline)
                        Text("移除行程").font(.caption)
                    }.foregroundStyle(.secondary)
                    Text(title).font(.title2.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message).font(.body).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                Button { deleteExclusiveMarkers.toggle() } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: deleteExclusiveMarkers ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(deleteExclusiveMarkers ? Color.primary : Color.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("同时删除独占地点").font(.body).foregroundStyle(.primary)
                            Text("其他行程仍在使用的地点会保留。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.plain)
                    .accessibilityValue(deleteExclusiveMarkers ? "已选" : "未选")
                    .accessibilityIdentifier("delete-\(kind)-markers")
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("取消").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.primary)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }.buttonStyle(.plain)
                    Button(role: .destructive) {
                        deleting = true
                        let includeMarkers = deleteExclusiveMarkers
                        dismiss()
                        action(includeMarkers)
                    } label: {
                        Text(title).font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.white).background(Color.red, in: Capsule())
                    }.buttonStyle(.plain).accessibilityIdentifier("confirm-delete-\(kind)")
                }
            }
            .padding(24)
            .disabled(deleting || store.saving)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { bottomSafeArea = proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.safeAreaInsets.bottom) { _, inset in bottomSafeArea = inset }
                }
            }
        .presentationDetents([.height(max(160, contentHeight - bottomSafeArea))])
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(deleting)
    }
}

extension View {
    func journeyError(store: AppStore, enabled: Bool = true) -> some View {
        modifier(JourneyErrorPresentation(store: store, enabled: enabled))
    }
}

private struct JourneyErrorPresentation: ViewModifier {
    @ObservedObject var store: AppStore
    let enabled: Bool
    @State private var resumeAfterDismiss = false
    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { enabled && store.errorMessage != nil },
            set: { if !$0 && enabled { store.errorMessage = nil } }), onDismiss: {
                if resumeAfterDismiss { resumeAfterDismiss = false; store.resumeFailedSave() }
            }) {
                JourneyErrorPanel(message: store.errorMessage ?? "", canResume: store.canResumeFailedSave) {
                    resumeAfterDismiss = $0
                    store.errorMessage = nil
                }
            }
    }
}

private struct JourneyErrorPanel: View {
    let message: String
    let canResume: Bool
    let close: (Bool) -> Void
    @State private var height: CGFloat = 280
    var body: some View {
        ViewThatFits(in: .vertical) {
            contents
            ScrollView { contents }
        }
        .presentationDetents([.height(height)])
        .presentationBackground(Color(uiColor: .systemBackground))
        .presentationDragIndicator(.hidden)
    }
    private var contents: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "exclamationmark.circle").font(.title2).foregroundStyle(.secondary)
            Text("未能完成操作").font(.title2.weight(.semibold))
            Text(message).font(.body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button { close(false) } label: {
                    Text("知道了").frame(maxWidth: .infinity, minHeight: 52)
                        .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                }.buttonStyle(.plain)
                if canResume {
                    Button { close(true) } label: {
                        Text("继续编辑").frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(Color(uiColor: .systemBackground))
                            .background(Color(uiColor: .label), in: Capsule())
                    }.buttonStyle(.plain)
                }
            }.font(.body.weight(.medium))
        }.padding(24).accessibilityIdentifier("journey-error-panel")
            .background(GeometryReader { proxy in
                Color.clear.onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, value in height = value }
            })
    }
}
