import XCTest
@testable import MapAnNai

final class ChatMarkdownTests: XCTestCase {
    func testMixedTextAlignmentAndEscapedPipes() {
        let blocks = ChatMarkdown.blocks("安排如下\n\n| 地点 | 时间 | 费用 |\n| :--- | :---: | ---: |\n| **咖啡** \\| 书店 | 09:00 | 20 |\n\n结束")
        XCTAssertEqual(blocks.count, 3)
        guard case .table(let table) = blocks[1] else { return XCTFail("Missing table") }
        XCTAssertEqual(table.alignments, [.leading, .center, .trailing])
        XCTAssertEqual(table.rows, [["**咖啡** | 书店", "09:00", "20"]])
    }
    func testFencedCodeAndIncompleteSeparatorStayText() {
        XCTAssertEqual(ChatMarkdown.blocks("```\n| a | b |\n| --- | --- |\n```"), [.text("```\n| a | b |\n| --- | --- |\n```")])
        XCTAssertEqual(ChatMarkdown.blocks("| a | b |\n| --"), [.text("| a | b |\n| --")])
    }
    func testStreamingRowsAndOptionalOuterPipes() {
        let blocks = ChatMarkdown.blocks("a | b\n--- | ---\nx | y\nz |")
        guard case .table(let table) = blocks.first else { return XCTFail("Missing table") }
        XCTAssertEqual(table.rows, [["x", "y"], ["z", ""]])
    }
}
