import SwiftUI

struct TripDeletionView: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DeletionConfirmationView(store: store, title: "删除旅行", message: "“\(trip.name)”及其每日行程将被删除。", kind: "trip") { includeMarkers in
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
    @ScaledMetric(relativeTo: .title2) private var titleHeight = 26

    var body: some View {
            VStack(spacing: 8) {
                Text(title).font(.title2.bold()).frame(height: titleHeight)
                VStack(spacing: 0) {
                Text(message)
                    .font(.body).foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                List(selection: Binding<Set<String>>(
                    get: { deleteExclusiveMarkers ? ["places"] : [] },
                    set: { deleteExclusiveMarkers = $0.contains("places") }
                )) {
                    Text("同时删除行程内所有标记").font(.body)
                        .foregroundStyle(.secondary)
                        .tag("places")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 0))
                        .accessibilityIdentifier("delete-\(kind)-markers")
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: 44)
                }
                .offset(y: 3)
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("取消").foregroundStyle(Color(uiColor: .systemBlue))
                            .frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered).tint(Color(uiColor: .systemGray))
                    Button(role: .destructive) {
                        deleting = true
                        let includeMarkers = deleteExclusiveMarkers
                        dismiss()
                        action(includeMarkers)
                    } label: {
                        Text(title).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).tint(.red)
                    .accessibilityIdentifier("confirm-delete-\(kind)")
                }
                .controlSize(.large)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 16)
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
        .presentationDragIndicator(.hidden)
        .interactiveDismissDisabled(deleting)
    }
}
