import Foundation

/// Pipe tables are parsed independently of inline Markdown. Incomplete streamed
/// rows stay readable, while fenced code always remains literal text.
enum ChatMarkdown {
    enum ColumnAlignment: Equatable { case leading, center, trailing }
    struct Table: Equatable {
        let headers: [String]
        let alignments: [ColumnAlignment]
        let rows: [[String]]
    }
    enum Block: Equatable { case text(String), table(Table) }

    static func blocks(_ source: String) -> [Block] {
        let lines = source.components(separatedBy: "\n")
        var result: [Block] = [], text: [String] = []
        var index = 0, fence: Character?
        func flush() {
            if !text.isEmpty { result.append(.text(text.joined(separator: "\n"))); text = [] }
        }
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let character = trimmed.first!
                if fence == character { fence = nil } else if fence == nil { fence = character }
                text.append(lines[index]); index += 1; continue
            }
            if fence == nil, index + 1 < lines.count,
               let headers = cells(lines[index]), let separators = cells(lines[index + 1]),
               headers.count == separators.count,
               separators.allSatisfy({ $0.range(of: "^:?-{3,}:?$", options: .regularExpression) != nil }) {
                flush()
                let alignments = separators.map { value -> ColumnAlignment in
                    if value.hasSuffix(":") { return value.hasPrefix(":") ? .center : .trailing }
                    return .leading
                }
                index += 2
                var rows: [[String]] = []
                while index < lines.count, let row = cells(lines[index]), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(Array((row + Array(repeating: "", count: headers.count)).prefix(headers.count)))
                    index += 1
                }
                result.append(.table(Table(headers: headers, alignments: alignments, rows: rows)))
            } else { text.append(lines[index]); index += 1 }
        }
        flush()
        return result
    }

    static func cells(_ line: String) -> [String]? {
        var values: [String] = [], cell = "", escaped = false, hasPipe = false
        for character in line.trimmingCharacters(in: .whitespaces) {
            if escaped {
                if character != "|" { cell.append("\\") }
                cell.append(character); escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "|" { values.append(cell); cell = ""; hasPipe = true }
            else { cell.append(character) }
        }
        if escaped { cell.append("\\") }
        values.append(cell)
        guard hasPipe else { return nil }
        if values.first?.trimmingCharacters(in: .whitespaces).isEmpty == true { values.removeFirst() }
        if values.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { values.removeLast() }
        guard !values.isEmpty else { return nil }
        return values.map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
