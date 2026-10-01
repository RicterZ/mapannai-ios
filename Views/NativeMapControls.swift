import SwiftUI
import UIKit

/// Native grouped glass on current systems; material keeps the same capsule on iOS 17–25.
struct NativeNavigationSurface: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular, in: .capsule)
        } else {
            content.background(.regularMaterial, in: Capsule())
        }
    }
}

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
        // Publishing results/layout while typing must not overwrite newer native keystrokes.
        if !bar.searchTextField.isFirstResponder, bar.text != text { bar.text = text }
    }
    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: NativePlaceSearchBar
        init(_ parent: NativePlaceSearchBar) { self.parent = parent }
        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            parent.text = searchText
            if searchText.isEmpty { parent.onClear() }
        }
        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            parent.text = searchBar.text ?? ""
            searchBar.resignFirstResponder()
            parent.onSearch()
        }
    }
}

/// Move the native bar (including its system glass groups), not its button labels.
/// The principal title compensates for this translation to retain its position.
struct JourneyToolbarContainerOffset: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.applyOffset()
        DispatchQueue.main.async { [weak controller] in controller?.applyOffset() }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.restoreOffset()
    }

    final class Controller: UIViewController {
        private weak var adjustedBar: UINavigationBar?
        override func loadView() {
            view = UIView(); view.isUserInteractionEnabled = false
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated); applyOffset()
        }
        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews(); applyOffset()
        }
        func applyOffset() {
            guard let bar = navigationController?.navigationBar else { return }
            if adjustedBar !== bar { restoreOffset(); adjustedBar = bar }
            bar.transform = CGAffineTransform(translationX: 0, y: -4)
        }
        func restoreOffset() {
            adjustedBar?.transform = .identity
            adjustedBar = nil
        }
    }
}
