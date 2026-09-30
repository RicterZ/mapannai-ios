import Foundation

// Tiptap can store an empty document as <p><br></p> or non-breaking spaces.
enum NoteContent {
    static func hasContent(_ html: String) -> Bool {
        let cleaned = html.replacingOccurrences(of: "(?is)<!--.*?-->|<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        if cleaned.range(of: "(?i)<(img|video|audio|iframe|hr)\\b", options: .regularExpression) != nil { return true }
        let text = cleaned.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)&nbsp;|&#0*160;|&#x0*a0;|&ZeroWidthSpace;|&#0*8203;|&#x0*200b;", with: "", options: .regularExpression)
            .filter { !$0.isWhitespace && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
        return !text.isEmpty
    }
}
