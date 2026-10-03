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
            AIChatTableLayout(columns: table.headers.count) {
                tableRow(table.headers, table: table, width: width, header: true, shaded: true)
                ForEach(Array(table.rows.enumerated()), id: \.offset) { index, row in
                    tableRow(row, table: table, width: width, header: false, shaded: !index.isMultiple(of: 2))
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

    private func tableRow(_ cells: [String], table: ChatMarkdown.Table, width: CGFloat, header: Bool, shaded: Bool) -> some View {
        Group {
            ForEach(cells.indices, id: \.self) { index in
                let alignment = table.alignments[index]
                Text(.init(cells[index]))
                    .fontWeight(header ? .semibold : .regular)
                    .multilineTextAlignment(alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .fixedSize(horizontal: true, vertical: true)
                    .frame(minWidth: width - 20, alignment: alignment == .center ? .center : alignment == .trailing ? .trailing : .leading)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment == .center ? .top : alignment == .trailing ? .topTrailing : .topLeading)
                    .background(shaded ? Color(uiColor: .tertiarySystemFill) : .clear)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color(uiColor: .separator)).frame(height: 0.5) }
                    .overlay(alignment: .trailing) { Rectangle().fill(Color(uiColor: .separator)).frame(width: 0.5) }
            }
        }
    }
}

/// Measure natural cell sizes first, then give every cell the full column width
/// and row height. Backgrounds and borders therefore form continuous stripes.
struct AIChatTableLayout: Layout {
    let columns: Int

    func dimensions(_ subviews: Subviews) -> (widths: [CGFloat], heights: [CGFloat]) {
        var widths = Array(repeating: CGFloat.zero, count: columns)
        var heights = Array(repeating: CGFloat.zero, count: (subviews.count + columns - 1) / columns)
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            widths[index % columns] = max(widths[index % columns], size.width)
            heights[index / columns] = max(heights[index / columns], size.height)
        }
        return (widths, heights)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = dimensions(subviews)
        return CGSize(width: sizes.widths.reduce(0, +), height: sizes.heights.reduce(0, +))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = dimensions(subviews)
        var y = bounds.minY
        for row in sizes.heights.indices {
            var x = bounds.minX
            for column in sizes.widths.indices {
                let index = row * columns + column
                if index < subviews.count {
                    subviews[index].place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                        proposal: ProposedViewSize(width: sizes.widths[column], height: sizes.heights[row]))
                }
                x += sizes.widths[column]
            }
            y += sizes.heights[row]
        }
    }
}
