import SwiftUI

struct TripDeletionView: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @State private var deleteExclusiveMarkers = false
    @State private var deleting = false
    @State private var failure: String?

    var body: some View {
        VStack(spacing: 12) {
                Text("删除旅行？").font(.title3.bold())
                Text("「\(trip.name)」及其每日行程将被删除。")
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
                        .accessibilityIdentifier("delete-trip-markers")
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
                            let success = await store.perform {
                                try await $0.deleteTrip(id: trip.id, deleteExclusiveMarkers: includeMarkers)
                            }
                            deleting = false
                            if success { dismiss() }
                            else { failure = store.errorMessage; store.errorMessage = nil }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if deleting { ProgressView() }
                            Text("删除旅行")
                        }.frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("confirm-delete-trip")
                }
            }
            .controlSize(.large)
            .padding(24)
            .disabled(deleting || store.saving)
            .presentationDetents([.height(280), .medium])
            .presentationDragIndicator(.hidden)
            .interactiveDismissDisabled(deleting)
    }
}
