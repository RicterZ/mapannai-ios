import SwiftUI

struct TripDeletionView: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    var body: some View {
        DeletionConfirmationView(store: store, title: "删除旅行", message: "「\(trip.name)」及其每日行程将被删除。", kind: "trip") { includeMarkers in
            await store.perform { try await $0.deleteTrip(id: trip.id, deleteExclusiveMarkers: includeMarkers) }
        }
    }
}

struct DayDeletionView: View {
    @ObservedObject var store: AppStore
    let day: TripDay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        DeletionConfirmationView(store: store, title: "删除当天", message: "\(day.date) 的安排将被删除，后续日期依次前移。", kind: "day") { includeMarkers in
            await store.deleteDay(day, deleteExclusiveMarkers: includeMarkers, animated: !reduceMotion)
        }
    }
}

private struct DeletionConfirmationView: View {
    @ObservedObject var store: AppStore
    let title: String
    let message: String
    let kind: String
    let action: (Bool) async -> Bool
    @State private var contentHeight: CGFloat = 250
    @Environment(\.dismiss) private var dismiss
    @State private var deleteExclusiveMarkers = false
    @State private var deleting = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 12) {
                Text("\(title)？").font(.title3.bold())
                Text(message)
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                List(selection: Binding<Set<String>>(
                    get: { deleteExclusiveMarkers ? ["places"] : [] },
                    set: { deleteExclusiveMarkers = $0.contains("places") }
                )) {
                    Text("同时删除独占地点")
                        .tag("places")
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .accessibilityIdentifier("delete-\(kind)-markers")
                }
                .environment(\.editMode, .constant(.active))
                .listStyle(.plain)
                .scrollDisabled(true)
                .scrollContentBackground(.hidden)
                .frame(height: 52)
                Text("共享地点会保留。不勾选则保留全部地点。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let failure { Text(failure).foregroundStyle(.red) }
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Text("取消").frame(maxWidth: .infinity)
                    }.buttonStyle(.bordered)
                    Button(role: .destructive) {
                        deleting = true
                        let includeMarkers = deleteExclusiveMarkers
                        Task {
                            let success = await action(includeMarkers)
                            deleting = false
                            if success { dismiss() }
                            else { failure = store.errorMessage; store.errorMessage = nil }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if deleting { ProgressView() }
                            Text(title)
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("confirm-delete-\(kind)")
                }
            }
            .controlSize(.large)
            .padding(20)
            .disabled(deleting || store.saving)
            .fixedSize(horizontal: false, vertical: true)
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { contentHeight = proxy.size.height }
                        .onChange(of: proxy.size.height) { _, height in contentHeight = height }
                }
            }
            .presentationDetents([.height(contentHeight)])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(deleting)
    }
}
