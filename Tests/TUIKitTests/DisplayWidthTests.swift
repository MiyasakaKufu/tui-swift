import XCTest
@testable import TUIKit

@TUIActor
final class DisplayWidthTests: XCTestCase {

    func testASCIIWidth() {
        XCTAssertEqual(DisplayWidth.width(of: "hello"), 5)
    }

    func testFullWidthCharacters() {
        XCTAssertEqual(DisplayWidth.width(of: "あ"), 2)
        XCTAssertEqual(DisplayWidth.width(of: "日本語"), 6)
        XCTAssertEqual(DisplayWidth.width(of: "Ａ"), 2)
    }

    func testMixedWidth() {
        XCTAssertEqual(DisplayWidth.width(of: "ab漢字"), 6)
    }

    func testCombiningMarksHaveNoWidth() {
        let combiningAcuteAccent = "\u{0301}"
        XCTAssertEqual(DisplayWidth.width(of: "e" + combiningAcuteAccent), 1)
    }

    func testControlCharactersHaveNoWidth() {
        XCTAssertEqual(DisplayWidth.width(of: "\u{07}"), 0)
    }

    func testEmojiIsWide() {
        XCTAssertEqual(DisplayWidth.width(of: "🎉"), 2)
    }

    func testPrefixDoesNotSplitWideCharacters() {
        XCTAssertEqual(String(DisplayWidth.prefix(of: "あいう", width: 3)), "あ")
        XCTAssertEqual(String(DisplayWidth.prefix(of: "あいう", width: 4)), "あい")
    }

    func testTruncateKeepsWithinLimit() {
        let result = DisplayWidth.truncate("abcdefgh", to: 5)
        XCTAssertEqual(result, "abcd…")
        XCTAssertEqual(DisplayWidth.width(of: result), 5)
    }

    func testTruncateReturnsOriginalWhenItFits() {
        XCTAssertEqual(DisplayWidth.truncate("abc", to: 5), "abc")
    }

    func testTruncateWithZeroLimit() {
        XCTAssertEqual(DisplayWidth.truncate("abc", to: 0), "")
    }
}
