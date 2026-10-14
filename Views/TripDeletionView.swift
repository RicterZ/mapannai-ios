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

struct DeletionConfirmationChoice: Identifiable {
    let id: String
    let title: String
    let action: () -> Void
}

struct DeletionConfirmationView: View {
    @ObservedObject var store: AppStore
    let title: String
    let message: String
    let kind: String
    var offersExclusiveMarkers = true
    var choices: [DeletionConfirmationChoice] = []
    var allowsQueuedWrites = false
    var independentOfAPISaving = false
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
                ForEach(choices) { choice in
                    Button(role: .destructive) {
                        deleting = true
                        dismiss()
                        choice.action()
                    } label: {
                        Text(choice.title).font(.body.weight(.medium))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(.red)
                        .accessibilityIdentifier("delete-\(kind)-\(choice.id)")
                }
                if offersExclusiveMarkers {
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
                }
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("取消").font(.body.weight(.medium)).frame(maxWidth: .infinity, minHeight: 52)
                            .foregroundStyle(.primary)
                            .background(Color(uiColor: .secondarySystemBackground), in: Capsule())
                    }.buttonStyle(.plain)
                        .accessibilityIdentifier("cancel-delete-\(kind)")
                    if choices.isEmpty {
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
            }
            .padding(24)
            .disabled(deleting || (!independentOfAPISaving && (choices.isEmpty && !allowsQueuedWrites ? store.saving : !store.canEditItinerary)))
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
        content.appAlert(isPresented: Binding(get: { enabled && store.errorMessage != nil },
            set: { if !$0 && enabled { store.errorMessage = nil } }), title: "未能完成操作", symbol: "exclamationmark.triangle", message: store.errorMessage ?? "", onDismiss: {
                if resumeAfterDismiss { resumeAfterDismiss = false; store.resumeFailedSave() }
            }, actions: [AppAlertAction(title: "知道了") { store.errorMessage = nil }] + (store.canResumeFailedSave ? [
                AppAlertAction(title: "继续编辑") { resumeAfterDismiss = true; store.errorMessage = nil }
            ] : []))
    }
}

struct AppAlertAction {
    let title: String
    var destructive = false
    let action: () -> Void
}
struct AppAlertCard: View {
    let title: String
    let symbol: String
    let message: String
    let actions: [AppAlertAction]
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 16) {
                Text(title).font(.system(size: 19, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .overlay(alignment: .leading) {
                        Image(systemName: symbol).font(.system(size: 20))
                            .foregroundStyle(.secondary).offset(x: -30).accessibilityHidden(true)
                    }
                    .padding(.horizontal, 30).frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                Text(message).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(24)
            Divider()
            HStack(spacing: 0) {
                ForEach(actions.indices, id: \.self) { index in
                    if index > 0 { Divider().frame(height: 48) }
                    Button(action: actions[index].action) {
                        Text(actions[index].title).font(.body.weight(index == actions.count - 1 ? .semibold : .regular))
                            .foregroundStyle(actions[index].destructive ? Color.red : Color(uiColor: .systemBlue))
                            .frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }.background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 22))
            .clipShape(RoundedRectangle(cornerRadius: 22)).frame(maxWidth: 340)
            .accessibilityIdentifier("app-alert-card")
    }
}
extension View {
    func appAlert(isPresented: Binding<Bool>, title: String, symbol: String, message: String,
                  onDismiss: @escaping () -> Void = {}, actions: [AppAlertAction]) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            ZStack {
                Color.clear.ignoresSafeArea()
                AppAlertCard(title: title, symbol: symbol, message: message, actions: actions).padding(24)
            }.presentationBackground(.clear)
        }

    }
}
