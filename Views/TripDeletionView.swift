import SwiftUI

struct TripDeletionView: View {
    @ObservedObject var store: AppStore
    let trip: Trip
    @Environment(\.dismiss) private var dismiss
    @State private var deleteExclusiveMarkers = false
    @State private var deleting = false
    @State private var failure: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("删除「\(trip.name)」及其每日行程？")
                    .font(.body)
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
                Text("关联多个旅行或多个日期的地点会保留。不勾选则保留全部地点。")
                    .font(.footnote).foregroundStyle(.secondary)
                if let failure { Text(failure).foregroundStyle(.red) }
                Group {
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
                        HStack {
                            Text("删除旅行")
                            Spacer()
                            if deleting { ProgressView() }
                        }.contentShape(Rectangle())
                    }
                    .buttonStyle(.borderedProminent).tint(.red)
                    .accessibilityIdentifier("confirm-delete-trip")
                }
                Spacer(minLength: 0)
            }
                .padding(20)
                .disabled(deleting || store.saving)
                .navigationTitle("删除旅行").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { dismiss() }.disabled(deleting)
                    }
                }
        }
        .presentationDetents([.height(320), .medium])
        .interactiveDismissDisabled(deleting)
    }
}
