import SwiftUI
import UIKit

struct NativePlaceSearchBar: UIViewRepresentable {
    @Binding var text: String
    var searching: Bool
    var onSearch: () -> Void
    var onClear: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = "搜索地点"
        bar.returnKeyType = .search
        bar.autocorrectionType = .no
        bar.delegate = context.coordinator
        bar.searchTextField.accessibilityIdentifier = "map-place-search"
        bar.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return bar
    }
    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        if bar.text != text { bar.text = text }
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativePlaceSearchBar
        init(_ parent: NativePlaceSearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
            if searchText.isEmpty { parent.onClear() }
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
            parent.onSearch()
        }
    }
}
