import XCTest
@testable import Clipstrate

final class NLSegmenterTests: XCTestCase {
    private let segmenter = NLSegmenter()

    func testMixedChineseEnglishAndPunctuation() {
        let tokens = segmenter.tokens(in: "你好，Clipstrate 123!")

        XCTAssertEqual(tokens.map(\.text), ["你", "好", "，", "Clipstrate", "123", "!"])
        XCTAssertEqual(tokens.map(\.isPunctuation), [false, false, true, false, false, true])
        XCTAssertEqual(tokens.map(\.id), Array(0..<tokens.count))
    }

    func testSourceRangesRecoverEveryToken() throws {
        let source = "复制 email@example.com，再见。"
        let tokens = segmenter.tokens(in: source)

        for token in tokens {
            let range = try XCTUnwrap(Range(token.sourceRange, in: source))
            XCTAssertEqual(String(source[range]), token.text)
        }
    }

    func testWhitespaceIsOmittedButSymbolsArePreserved() {
        let tokens = segmenter.tokens(in: "Hi \n\t👋!")

        XCTAssertEqual(tokens.map(\.text), ["Hi", "👋", "!"])
        XCTAssertEqual(tokens.map(\.isPunctuation), [false, false, true])
    }

    func testEmptyAndWhitespaceOnlyInput() {
        XCTAssertTrue(segmenter.tokens(in: "").isEmpty)
        XCTAssertTrue(segmenter.tokens(in: " \n\t").isEmpty)
    }

    func testTokenizes1000CharactersUnder30Milliseconds() {
        let source = String(String(repeating: "中文Clipstrate，", count: 100).prefix(1_000))
        XCTAssertEqual(source.count, 1_000)

        // Warm NaturalLanguage's process-wide resources before measuring the
        // steady-state path used by the preheated app.
        _ = segmenter.tokens(in: source)

        let clock = ContinuousClock()
        let start = clock.now
        let tokens = segmenter.tokens(in: source)
        let elapsed = start.duration(to: clock.now)

        XCTAssertFalse(tokens.isEmpty)
        XCTAssertLessThan(elapsed, .milliseconds(30))
    }
}
