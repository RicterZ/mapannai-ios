import SwiftUI
import UIKit
import WebKit

// HTML is rendered as content only. The app, map and editor are native UIKit/SwiftUI.
struct HTMLReader: UIViewRepresentable {
    let html: String
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false; web.backgroundColor = .clear; web.scrollView.isScrollEnabled = true
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        let prefix = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline';">
        <style>body{font:16px -apple-system;color:#253c37;margin:0;line-height:1.6}img{max-width:100%;height:auto;border-radius:12px}p{margin:0 0 12px}a{color:#24765e}</style></head><body>
        """
        web.loadHTMLString(prefix + html + "</body></html>", baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var lastHTML: String? }
}
@MainActor final class RichEditorController: ObservableObject {
    weak var textView: UITextView?
    var changed = false
    private func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view = textView else { return }
        let range = view.selectedRange
        if range.length == 0 {
            let font = (view.typingAttributes[.font] as? UIFont) ?? .systemFont(ofSize: 16)
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { view.typingAttributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
        } else {
            let mutable = NSMutableAttributedString(attributedString: view.attributedText)
            mutable.enumerateAttribute(.font, in: range) { value, r, _ in
                let font = (value as? UIFont) ?? .systemFont(ofSize: 16)
                var traits = font.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { mutable.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: r) }
            }
            view.attributedText = mutable; view.selectedRange = range; changed = true
        }
    }
    func toggleBold() { toggle(.traitBold) }
    func toggleItalic() { toggle(.traitItalic) }
    func insertBullet() { textView?.insertText("\n• "); changed = true }
    func exportHTML(original: String) -> String {
        guard changed, let view = textView else { return original }
        guard let data = try? view.attributedText.data(from: NSRange(location: 0, length: view.attributedText.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.html]),
              let html = String(data: data, encoding: .utf8) else { return original }
        return html
    }
}
struct RichEditor: UIViewRepresentable {
    @ObservedObject var controller: RichEditorController
    let initialHTML: String
    func makeCoordinator() -> Coordinator { Coordinator(controller) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView(); view.delegate = context.coordinator; view.backgroundColor = .clear
        view.font = .systemFont(ofSize: 16); view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        view.allowsEditingTextAttributes = true
        if !initialHTML.isEmpty, let data = initialHTML.data(using: .utf8),
           let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil) {
            let mutable = NSMutableAttributedString(attributedString: text)
            mutable.addAttribute(.foregroundColor, value: UIColor(Theme.ink), range: NSRange(location: 0, length: text.length))
            view.attributedText = mutable
        }
        view.typingAttributes = [.font: UIFont.systemFont(ofSize: 16), .foregroundColor: UIColor(Theme.ink)]
        controller.textView = view; return view
    }
    func updateUIView(_ view: UITextView, context: Context) {}
    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: RichEditorController
        init(_ controller: RichEditorController) { self.controller = controller }
        func textViewDidChange(_ textView: UITextView) { controller.changed = true }
    }
}
