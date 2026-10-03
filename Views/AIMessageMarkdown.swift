import SwiftUI

struct AIMessageMarkdown: View {
    let content: String
    let availableWidth: CGFloat
    @ScaledMetric(relativeTo: .body) private var columnWidth = 136

    var body: some View {
        let blocks = ChatMarkdown.blocks(content)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text): Text(.init(text)).fixedSize(horizontal: false, vertical: true)
                case .table(let table): tableView(table)
                }
            }
        }
    }

    private func tableView(_ table: ChatMarkdown.Table) -> some View {
        let width = max(columnWidth, availableWidth / CGFloat(table.headers.count))
        return ScrollView(.horizontal) {
            Grid(alignment: .topLeading, horizontalSpacing: 0, verticalSpacing: 0) {
                tableRow(table.headers, table: table, width: width, header: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, table: table, width: width, header: false)
                        .background(index.isMultiple(of: 2) ? Color.clear : Color(uiColor: .tertiarySystemFill))
                }
            }
            .background(Color(uiColor: .systemBackground).opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(uiColor: .separator), lineWidth: 0.5))
            .padding(.bottom, 4)
        }
        .frame(width: availableWidth, alignment: .leading)
        .accessibilityIdentifier("ai-markdown-table")
    }

    private func tableRow(_ cells: [String], table: ChatMarkdown.Table, width: CGFloat, header: Bool) -> some View {
        GridRow {
            ForEach(cells.indices, id: \.self) { index in
                let alignment = table.alignments[index]
                Text(.init(cells[index]))
                    .fontWeight(header ? .semibold : .regular)
                    .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: width - 20, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .padding(10)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .background(header ? Color(uiColor: .tertiarySystemFill) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5) }
            }
        }
    }
}
