import SwiftUI

/// Read-only demo fixtures for editor screenshots; never used with a configured server.
struct JourneyEditorPreview: View {
    @ObservedObject var store: AppStore
    let kind: String
    var body: some View {
        if kind == "trip", let trip = store.trips.first {
            TripEditorView(store: store, trip: trip)
        } else if kind == "place-edit", let marker = store.markers.first {
            MarkerEditorView(store: store, initial: MarkerDraft(marker: marker))
        } else if kind == "place-add", let marker = store.markers.first {
            MarkerEditorView(store: store, initial: MarkerDraft(coordinates: marker.coordinates,
                title: "京都站", address: "京都市下京区东盐小路町"))
        } else if kind == "place-new", let marker = store.markers.first {
            MarkerEditorView(store: store, initial: MarkerDraft(coordinates: marker.coordinates))
        } else if let day = store.trips.first?.days.first {
            ChainEditorView(store: store, request: ChainEditRequest(day: day,
                index: kind == "route-edit" ? 0 : nil, ids: kind == "route-edit" ? day.chains.first ?? [] : []))
        }
    }
}
