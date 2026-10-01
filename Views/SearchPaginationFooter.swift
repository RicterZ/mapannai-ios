import SwiftUI

/// A lazy List row triggers the next page only when it reaches the viewport.
struct SearchPaginationFooter: View {
    @ObservedObject var store: AppStore
    var body: some View {
        if let error = store.searchPageError {
            Button { Task { await store.loadMoreSearch() } } label: {
                Label(error, systemImage: "arrow.clockwise").fullRowActionLabel()
            }.buttonStyle(.plain).foregroundStyle(Theme.accent)
                .accessibilityIdentifier("search-page-retry")
        } else if store.searchHasMore || store.loadingMoreSearch {
            HStack {
                Spacer()
                ProgressView().accessibilityLabel("加载更多地点")
                Spacer()
            }.frame(minHeight: 44)
                .accessibilityIdentifier("search-page-loading")
                .task(id: store.searchPageRevision) { await store.loadMoreSearch() }
        }
    }
}
