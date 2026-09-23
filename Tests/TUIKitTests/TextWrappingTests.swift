import XCTest
@testable import TUIKit

@MainActor
final class TextWrappingTests: XCTestCase {

    func testNewlinesAlwaysSplit() async {
        let lines = TextWrapping.wrap("a\nb", width: 10, mode: .none)
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testTabsExpandBeforeWrapping() async {
        let lines = TextWrapping.wrap("a\tb", width: 10, mode: .none)
        XCTAssertEqual(lines, ["a   b"])
    }

    func testTabsAlignToTabStopsOnEachLine() async {
        let lines = TextWrapping.wrap("ab\tc\nabcd\te", width: 20, mode: .none)
        XCTAssertEqual(lines, ["ab  c", "abcd    e"])
    }

    func testTabStopsResetAfterCRLF() async {
        let lines = TextWrapping.wrap("ab\tc\r\nabcd\te", width: 20, mode: .none)
        XCTAssertEqual(lines, ["ab  c", "abcd    e"])
    }

    func testExpandedTabsAreSubjectToWrapping() async {
        let lines = TextWrapping.wrap("a\tb", width: 4, mode: .character)
        XCTAssertEqual(lines, ["a   ", "b"])
    }

    func testTabSizeIsConfigurable() async {
        XCTAssertEqual(TextWrapping.wrap("a\tb", width: 20, mode: .none, tabSize: 8), ["a       b"])
        XCTAssertEqual(TextWrapping.wrap("a\tb", width: 20, mode: .none, tabSize: 0), ["ab"])
    }

    func testCRLFSplitsLines() async {
        let lines = TextWrapping.wrap("ab\r\ncd", width: 10, mode: .none)
        XCTAssertEqual(lines, ["ab", "cd"])
    }

    func testLoneCarriageReturnSplitsLines() async {
        let lines = TextWrapping.wrap("ab\rcd", width: 10, mode: .none)
        XCTAssertEqual(lines, ["ab", "cd"])
    }

    func testCRLFSplitsLinesInWordMode() async {
        let lines = TextWrapping.wrap("the quick\r\nbrown fox", width: 10, mode: .word)
        XCTAssertEqual(lines, ["the quick", "brown fox"])
    }

    func testTrailingCRLFProducesEmptyLastLine() async {
        XCTAssertEqual(TextWrapping.wrap("ab\r\n", width: 10, mode: .none), ["ab", ""])
        XCTAssertEqual(TextWrapping.wrap("ab\r", width: 10, mode: .none), ["ab", ""])
    }

    func testNoneModeTruncates() async {
        let lines = TextWrapping.wrap("abcdef", width: 3, mode: .none)
        XCTAssertEqual(lines, ["abc"])
    }

    func testTruncateModeAddsEllipsis() async {
        let lines = TextWrapping.wrap("abcdef", width: 4, mode: .truncate)
        XCTAssertEqual(lines, ["abc…"])
    }

    func testCharacterWrapping() async {
        let lines = TextWrapping.wrap("abcdef", width: 2, mode: .character)
        XCTAssertEqual(lines, ["ab", "cd", "ef"])
    }

    func testCharacterWrappingKeepsWideCharactersIntact() async {
        let lines = TextWrapping.wrap("あいう", width: 3, mode: .character)
        XCTAssertEqual(lines, ["あ", "い", "う"])
    }

    func testWordWrapping() async {
        let lines = TextWrapping.wrap("the quick brown fox", width: 10, mode: .word)
        XCTAssertEqual(lines, ["the quick", "brown fox"])
    }

    func testWordWrappingBreaksOverlongWords() async {
        let lines = TextWrapping.wrap("abcdefghij kl", width: 4, mode: .word)
        XCTAssertEqual(lines, ["abcd", "efgh", "ij", "kl"])
    }

    func testEmptyStringProducesOneEmptyLine() async {
        XCTAssertEqual(TextWrapping.wrap("", width: 10, mode: .word), [""])
    }
}
