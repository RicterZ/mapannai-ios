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
    private static func visibleHTML(_ html: String) -> String {
        html.replacingOccurrences(of: "(?is)<!--.*?(?:-->|$)|<(script|style|head|title|template|noscript)\\b[^>]*>.*?(?:</\\1\\s*>|$)", with: " ", options: .regularExpression)
    }
    static func excerpt(_ html: String) -> String {
        var text = visibleHTML(html).replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        let numeric = try! NSRegularExpression(pattern: "&#([0-9]+|[xX][0-9a-fA-F]+);")
        for match in numeric.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range(at: 1), in: text), let whole = Range(match.range, in: text) else { continue }
            let raw = String(text[range])
            let value = raw.lowercased().hasPrefix("x") ? UInt32(raw.dropFirst(), radix: 16) : UInt32(raw)
            if let value, let scalar = UnicodeScalar(value) { text.replaceSubrange(whole, with: String(scalar)) }
        }
        for (entity, value) in [("&quot;", "\""), ("&apos;", "'"), ("&nbsp;", " "), ("&ZeroWidthSpace;", ""), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.filter { $0 != "\u{200B}" && $0 != "\u{FEFF}" }
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
    private static func evaluate(_ html: String) -> Bool {
        let cleaned = visibleHTML(html)
        return cleaned.range(of: "(?i)<img\\b", options: .regularExpression) != nil || !excerpt(cleaned).isEmpty
    }
}
