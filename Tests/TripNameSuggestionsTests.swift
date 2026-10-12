import XCTest
@testable import MapAnNai

final class TripNameSuggestionsTests: XCTestCase {
    func testVocabularyAndRandomRolls() {
        XCTAssertEqual(Set(TripNameSuggestions.places).count, 30)
        XCTAssertEqual(Set(TripNameSuggestions.themes).count, 20)
        for words in [TripNameSuggestions.places, TripNameSuggestions.themes] {
            XCTAssertTrue(words.allSatisfy { $0.count == 2 })
            for _ in 0..<100 {
                let roll = TripNameSuggestions.roll(from: words[0], words: words)
                XCTAssertEqual(roll.first, words[0])
                XCTAssertTrue((4...5).contains(roll.count - 1))
                XCTAssertTrue(roll.allSatisfy { words.contains($0) })
            }
        }
    }

    func testSharedProgressAcceleratesAndDeceleratesWithoutOvershoot() {
        let duration = TripNameSuggestions.rollDuration
        let samples = (0...10).map { TripNameSuggestions.progress(elapsed: duration * Double($0) / 10) }
        XCTAssertEqual(samples.first, 0)
        XCTAssertEqual(samples.last, 1)
        XCTAssertEqual(TripNameSuggestions.progress(elapsed: -1), 0)
        XCTAssertEqual(TripNameSuggestions.progress(elapsed: duration + 1), 1)
        XCTAssertTrue(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
        XCTAssertGreaterThan(samples[5] - samples[4], samples[1] - samples[0])
        XCTAssertGreaterThan(samples[5] - samples[4], samples[10] - samples[9])
    }
}
