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
    var onBeginEditing: () -> Void = {}

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
        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) { parent.onBeginEditing() }
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
    var offset: CGFloat = -4
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(); controller.offset = offset; return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.offset = offset
        controller.applyOffset()
        DispatchQueue.main.async { [weak controller] in controller?.applyOffset() }
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.dismantle()
    }

    final class Controller: UIViewController {
        private final class Owners {
            let controllers = NSHashTable<Controller>.weakObjects()
            let original: CGAffineTransform
            init(_ original: CGAffineTransform) { self.original = original }
        }
        private static let bars = NSMapTable<UINavigationBar, Owners>.weakToStrongObjects()
        private weak var adjustedBar: UINavigationBar?
        private var dismantled = false
        var offset: CGFloat = -4
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
            guard !dismantled, let bar = navigationController?.navigationBar else { return }
            if adjustedBar !== bar {
                restoreOffset(); adjustedBar = bar
                let owners = Self.bars.object(forKey: bar) ?? Owners(bar.transform)
                owners.controllers.add(self)
                Self.bars.setObject(owners, forKey: bar)
            }
            UIView.performWithoutAnimation { bar.transform = CGAffineTransform(translationX: 0, y: offset) }
        }
        func dismantle() {
            dismantled = true
            restoreOffset()
        }
        private func restoreOffset() {
            if let bar = adjustedBar, let owners = Self.bars.object(forKey: bar) {
                owners.controllers.remove(self)
                if owners.controllers.allObjects.isEmpty {
                    UIView.performWithoutAnimation { bar.transform = owners.original }
                    Self.bars.removeObject(forKey: bar)
                }
            }
            adjustedBar = nil
        }
    }
}
