import SwiftUI
import UIKit
import WebKit

private enum NoteEditorTypography {
    static var bodyFont: UIFont { UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 18)) }
}

enum LinkedNoteText {
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return result }
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text),
                  let attributedRange = Range(range, in: result) else { continue }
            result[attributedRange].link = url
        }
        return result
    }
}

// HTML is rendered as content only. The app, map and editor are native UIKit/SwiftUI.
struct HTMLReader: UIViewRepresentable {
    let html: String
    @Binding var contentHeight: CGFloat
    var onImage: (URL) -> Void = { _ in }
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.dataDetectorTypes = [.link]
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.isOpaque = false; web.backgroundColor = .clear
        web.scrollView.pinchGestureRecognizer?.isEnabled = false
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.imageTapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        web.addGestureRecognizer(tap)
        web.scrollView.isScrollEnabled = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        context.coordinator.observe(web)
        return web
    }
    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $contentHeight
        context.coordinator.onImage = onImage
        guard context.coordinator.lastHTML != html else { return }
        context.coordinator.lastHTML = html
        let prefix = """
        <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src https: data:; style-src 'unsafe-inline';">
        <style>html,body{padding:0}body{overflow-wrap:anywhere;font:16px -apple-system;color:#253c37;margin:0;line-height:1.6}img{max-width:100%;height:auto;border-radius:12px}p{margin:0 0 12px}a{color:#24765e}</style></head><body>
        """
        web.loadHTMLString(prefix + html + "</body></html>", baseURL: nil)
    }
    func makeCoordinator() -> Coordinator { Coordinator(height: $contentHeight) }
    static func dismantleUIView(_ web: WKWebView, coordinator: Coordinator) {
        coordinator.observation = nil
        web.stopLoading()
    }
    final class Coordinator: NSObject, WKNavigationDelegate, UIGestureRecognizerDelegate {
        var onImage: (URL) -> Void = { _ in }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool { true }
        @objc func imageTapped(_ tap: UITapGestureRecognizer) {
            guard tap.state == .ended, let web = tap.view as? WKWebView else { return }
            let point = tap.location(in: web)
            // Run only our DOM lookup in an isolated world; note scripts stay disabled.
            let script = "var e=document.elementFromPoint(\(point.x),\(point.y)); e && e.tagName === 'IMG' ? e.src : null"
            web.evaluateJavaScript(script, in: nil, in: .defaultClient) { [weak self] result in
                guard case .success(let value) = result, let source = value as? String,
                      let url = URL(string: source), ["https", "data"].contains(url.scheme?.lowercased() ?? "") else { return }
                self?.onImage(url)
            }
        }
        var lastHTML: String?
        var height: Binding<CGFloat>
        var observation: NSKeyValueObservation?
        init(height: Binding<CGFloat>) { self.height = height; super.init() }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated else {
                decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
                return
            }
            decisionHandler(.cancel)
            guard let url = navigationAction.request.url,
                  ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") else { return }
            UIApplication.shared.open(url)
        }
        func observe(_ web: WKWebView) {
            // WebKit updates contentSize again when layout or inline images finish loading.
            observation = web.scrollView.observe(\.contentSize, options: [.new]) { [weak self] scroll, _ in
                let measured = max(1, ceil(scroll.contentSize.height))
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.observation != nil,
                          abs(self.height.wrappedValue - measured) > 0.5 else { return }
                    self.height.wrappedValue = measured
                }
            }
        }
    }
}
@MainActor final class RichEditorController: ObservableObject {
    weak var textView: UITextView?
    var changed = false
    private func toggle(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view = textView else { return }
        let range = view.selectedRange
        if range.length == 0 {
            let font = (view.typingAttributes[.font] as? UIFont) ?? NoteEditorTypography.bodyFont
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) { view.typingAttributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize) }
        } else {
            let mutable = NSMutableAttributedString(attributedString: view.attributedText)
            mutable.enumerateAttribute(.font, in: range) { value, r, _ in
                let font = (value as? UIFont) ?? NoteEditorTypography.bodyFont
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
    func insertNumberedItem() { textView?.insertText("\n1. "); changed = true }
    func toggleUnderline() {
        guard let view = textView else { return }
        let range = view.selectedRange
        let current = (view.typingAttributes[.underlineStyle] as? Int) ?? 0
        let value = current == 0 ? NSUnderlineStyle.single.rawValue : 0
        if range.length == 0 { view.typingAttributes[.underlineStyle] = value }
        else {
            let text = NSMutableAttributedString(attributedString: view.attributedText)
            text.addAttribute(.underlineStyle, value: value, range: range)
            view.attributedText = text; view.selectedRange = range
        }
        changed = true
    }
    func setHeading(_ heading: Bool) {
        guard let view = textView else { return }
        let range = (view.text as NSString).paragraphRange(for: view.selectedRange)
        let font = heading ? UIFont.preferredFont(forTextStyle: .title2) : NoteEditorTypography.bodyFont
        if range.length > 0 {
            let text = NSMutableAttributedString(attributedString: view.attributedText)
            text.addAttribute(.font, value: font, range: range)
            view.attributedText = text; view.selectedRange = NSRange(location: min(view.selectedRange.location, text.length), length: 0)
        }
        view.typingAttributes[.font] = font
        changed = true
    }

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
        view.font = NoteEditorTypography.bodyFont; view.adjustsFontForContentSizeCategory = true; view.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        view.allowsEditingTextAttributes = true
        // HTML import spins a run loop. Defer it until SwiftUI has finished creating
        // the view so adaptive editor sizing cannot re-enter the layout graph.
        let html = initialHTML
        Task { @MainActor [weak view] in
            guard let view, !controller.changed, !html.isEmpty,
                  let data = html.data(using: .utf8),
                  let text = try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil),
                  !controller.changed else { return }
            let mutable = NSMutableAttributedString(attributedString: text)
            let fullRange = NSRange(location: 0, length: text.length)
            mutable.enumerateAttribute(.font, in: fullRange) { value, range, _ in
                let original = (value as? UIFont) ?? .systemFont(ofSize: 18)
                let descriptor = UIFont.systemFont(ofSize: 18).fontDescriptor
                    .withSymbolicTraits(original.fontDescriptor.symbolicTraits) ?? UIFont.systemFont(ofSize: 18).fontDescriptor
                let font = UIFontMetrics(forTextStyle: .body).scaledFont(
                    for: UIFont(descriptor: descriptor, size: max(18, original.pointSize)))
                mutable.addAttribute(.font, value: font, range: range)
            }
            mutable.addAttribute(.foregroundColor, value: UIColor(Theme.ink), range: fullRange)
            view.attributedText = mutable
            view.typingAttributes = [.font: NoteEditorTypography.bodyFont, .foregroundColor: UIColor(Theme.ink)]
        }
        view.typingAttributes = [.font: NoteEditorTypography.bodyFont, .foregroundColor: UIColor(Theme.ink)]
        controller.textView = view; return view
    }
    func updateUIView(_ view: UITextView, context: Context) {}
    final class Coordinator: NSObject, UITextViewDelegate {
        let controller: RichEditorController
        init(_ controller: RichEditorController) { self.controller = controller }
        func textViewDidChange(_ textView: UITextView) { controller.changed = true }
    }
}

struct NoteImageSelection: Identifiable {
    let id = UUID()
    let url: URL
}

struct NoteImagePreview: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var failed = false
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let image { ZoomableNoteImage(image: image) }
                else if failed { Text("图片加载失败").foregroundStyle(.white) }
                else { ProgressView().tint(.white) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 20))
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.white).padding(12).accessibilityLabel("关闭图片预览")
        }
        .task(id: url) {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                image = UIImage(data: data)
                failed = image == nil
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

private struct ZoomableNoteImage: UIViewRepresentable {
    let image: UIImage
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.delegate = context.coordinator
        scroll.minimumZoomScale = 1
        scroll.maximumZoomScale = 5
        scroll.contentInsetAdjustmentBehavior = .never
        let imageView = context.coordinator.imageView
        imageView.image = image
        imageView.contentMode = .scaleAspectFit
        scroll.addSubview(imageView)
        return scroll
    }
    func updateUIView(_ scroll: UIScrollView, context: Context) {
        context.coordinator.imageView.image = image
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIScrollView, context: Context) -> CGSize? {
        let size = CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
        if size.width > 0 && size.height > 0 && context.coordinator.baseSize != size {
            uiView.zoomScale = 1
            context.coordinator.baseSize = size
            context.coordinator.imageView.frame = CGRect(origin: .zero, size: size)
            uiView.contentSize = size
        }
        return size
    }
    final class Coordinator: NSObject, UIScrollViewDelegate {
        let imageView = UIImageView()
        var baseSize = CGSize.zero
        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    }
}
