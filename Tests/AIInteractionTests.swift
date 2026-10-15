import XCTest
@testable import MapAnNai

final class AIInteractionTests: XCTestCase {
    private func prompt(_ input: String) throws -> AIInteractionPrompt {
        try JSONDecoder().decode(AIInteractionPrompt.self, from: Data("{\"id\":\"prompt\",\"token\":\"test-only\",\"deadline\":2000000000000,\"input\":\(input)}".utf8))
    }
    func testChoiceEventAndSelectionValidation() throws {
        let p = try prompt(#"{"kind":"ask_choice","question":"偏好？","multiple":true,"maxSelections":2,"options":[{"id":"a","label":"自然"},{"id":"b","label":"城市"}]}"#)
        XCTAssertTrue(p.supported)
        XCTAssertEqual(p.expires.timeIntervalSince1970, 2_000_000_000)
        try p.validate(.choices(["a", "b"]))
        for ids in [[], ["a", "a"], ["unknown"], ["a", "b", "c"]] {
            XCTAssertThrowsError(try p.validate(.choices(ids)))
        }
        let value = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AIInteractionSelection.choices(["a"]))) as? [String]
        XCTAssertEqual(value, ["a"])
        let event = try JSONDecoder().decode(AIEvent.self, from: Data("{\"type\":\"interaction\",\"prompt\":\(String(data: JSONEncoder().encode(InteractionFixture()), encoding: .utf8)!)}".utf8))
        XCTAssertEqual(event.prompt?.input.kind, "ask_choice")
    }
    private struct InteractionFixture: Encodable {
        let id = "p", token = "test-only"
        let deadline = 2000000000000.0
        let input = ["kind": "ask_choice", "question": "test"]
    }
    func testDateRangeUsesLocalWallTimeAndRejectsInvalidDates() throws {
        let p = try prompt(#"{"kind":"ask_datetime","question":"何时？","mode":"datetime_range","timezone":"Asia/Tokyo"}"#)
        try p.validate(.datetime(start: "2026-10-15T09:00", end: "2026-10-16T10:00"))
        XCTAssertThrowsError(try p.validate(.datetime(start: "2026-10-15T09:00", end: "2026-10-14T10:00")))
        XCTAssertThrowsError(try p.validate(.datetime(start: "2026-02-30T09:00", end: "2026-03-01T09:00")))
        XCTAssertThrowsError(try p.validate(.datetime(start: "2026-10-15T09:00Z", end: nil)))
        let f = AIInteractionPrompt.formatter(format: "yyyy-MM-dd'T'HH:mm", timezone: "Asia/Tokyo")
        XCTAssertEqual(f.string(from: Date(timeIntervalSince1970: 0)), "1970-01-01T09:00")
    }
    func testPreviewValidationAndUnsupportedKind() throws {
        let p = try prompt(#"{"kind":"preview_itinerary","question":"如何？","title":"草案","days":[{"date":"2026-10-15","title":"东京","places":["公园"]}]}"#)
        try p.validate(.preview(action: "revise", feedback: "轻松一些"))
        XCTAssertThrowsError(try p.validate(.preview(action: "save", feedback: "")))
        XCTAssertThrowsError(try p.validate(.preview(action: "continue", feedback: String(repeating: "x", count: 2001))))
        let unsupported = try prompt(#"{"kind":"future_tool","question":"test"}"#)
        XCTAssertFalse(unsupported.supported)
    }
    func testHistoryPreservesCardsAndSelectionsWithoutPromptToken() throws {
        let p = try prompt(#"{"kind":"ask_choice","question":"偏好？","options":[{"id":"a","label":"自然"},{"id":"b","label":"城市"}]}"#)
        var conversation = AIConversation()
        conversation.interactions = [AIInteractionRecord(id: p.id, input: p.input, messageIndex: 2, selection: .choices(["a"]), ended: true)]
        let data = try JSONEncoder().encode(conversation)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("test-only"))
        let restored = try JSONDecoder().decode(AIConversation.self, from: data)
        XCTAssertEqual(restored.interactions?.first?.messageIndex, 2)
        guard case .choices(let ids) = restored.interactions?.first?.selection else { return XCTFail("Missing selected choices") }
        XCTAssertEqual(ids, ["a"])
        XCTAssertEqual(restored.interactions?.first?.prompt.token, "")
        for selection in [AIInteractionSelection.datetime(start: "2026-10-15", end: "2026-10-16"), .preview(action: "revise", feedback: "休息")] {
            let encoded = try JSONEncoder().encode(selection)
            let decoded = try JSONDecoder().decode(AIInteractionSelection.self, from: encoded)
            XCTAssertEqual(try JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? NSDictionary,
                           try JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        }
        let legacy = Data(#"{"id":"00000000-0000-0000-0000-000000000001","title":"旧会话","messages":[]}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode(AIConversation.self, from: legacy).interactions)
    }
    func testDeclineChoiceRoundTripsAndDoesNotApplyToOtherTools() throws {
        let choice = try prompt(#"{"kind":"ask_choice","question":"偏好？","options":[{"id":"a","label":"自然"},{"id":"b","label":"城市"}]}"#)
        try choice.validate(.none)
        let data = try JSONEncoder().encode(AIInteractionSelection.none)
        XCTAssertEqual(try JSONSerialization.jsonObject(with: data) as? [String: String], ["action": "none"])
        guard case .none = try JSONDecoder().decode(AIInteractionSelection.self, from: data) else { return XCTFail("Missing decline") }
        let date = try prompt(#"{"kind":"ask_datetime","question":"何时？","mode":"date","timezone":"Asia/Tokyo"}"#)
        XCTAssertThrowsError(try date.validate(.none))
        let message = AIMessage(role: "tool", content: #"{"status":"declined","selection":null}"#, name: "ask_choice")
        XCTAssertEqual(message.interactionSummary, "都不选，改用文字说明")
        let record = AIInteractionRecord(id: "test", input: choice.input, messageIndex: 1, selection: AIInteractionSelection.none, ended: true)
        let restored = try JSONDecoder().decode(AIInteractionRecord.self, from: JSONEncoder().encode(record))
        guard case .none? = restored.selection else { return XCTFail("History lost decline") }
    }
    func testChinaRegionsMatchWebAndForeignCoordinatesStayUnchanged() {
        for (lat, lng) in [(39.9,116.4), (31.2,121.5), (18.25,109.5), (43.8,87.6)] {
            XCTAssertTrue(Coordinates.inChina(Coordinate(latitude: lat, longitude: lng)))
        }
        for (lat, lng) in [(35.7,139.7), (25.03,121.56), (21.03,105.85), (37.56,126.98), (43.12,131.89), (47.92,106.92)] {
            let p = Coordinate(latitude: lat, longitude: lng)
            XCTAssertFalse(Coordinates.inChina(p))
            XCTAssertEqual(Coordinates.gcj(p), p)
        }
        XCTAssertFalse(Coordinates.inChina(Coordinate(latitude: .nan, longitude: 116)))
    }
}
