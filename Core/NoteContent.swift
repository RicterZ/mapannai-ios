import Foundation

// Tiptap can store an empty document as <p><br></p> or non-breaking spaces.
enum NoteContent {
    private static let cache: NSCache<NSString, NSNumber> = {
        let value = NSCache<NSString, NSNumber>(); value.countLimit = 256; value.totalCostLimit = 8 * 1024 * 1024
        return value
    }()
    static func hasContent(_ html: String) -> Bool {
        let key = html as NSString
        if let result = cache.object(forKey: key) { return result.boolValue }
        let result = evaluate(html)
        cache.setObject(NSNumber(value: result), forKey: key, cost: key.length * 2)
        return result
    }
    private static func evaluate(_ html: String) -> Bool {
        let cleaned = html.replacingOccurrences(of: "(?is)<!--.*?-->|<(script|style)\\b[^>]*>.*?</\\1>", with: "", options: .regularExpression)
        if cleaned.range(of: "(?i)<(img|video|audio|iframe|hr)\\b", options: .regularExpression) != nil { return true }
        let text = cleaned.replacingOccurrences(of: "<[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "(?i)&nbsp;|&#0*160;|&#x0*a0;|&ZeroWidthSpace;|&#0*8203;|&#x0*200b;", with: "", options: .regularExpression)
            .filter { !$0.isWhitespace && $0 != "\u{200B}" && $0 != "\u{FEFF}" }
        return !text.isEmpty
    }
}
