import XCTest
@testable import TUIKit

final class TextWrappingTests: XCTestCase {

    func testNewlinesAlwaysSplit() {
        let lines = TextWrapping.wrap("a\nb", width: 10, mode: .none)
        XCTAssertEqual(lines, ["a", "b"])
    }

    func testNoneModeTruncates() {
        let lines = TextWrapping.wrap("abcdef", width: 3, mode: .none)
        XCTAssertEqual(lines, ["abc"])
    }

    func testTruncateModeAddsEllipsis() {
        let lines = TextWrapping.wrap("abcdef", width: 4, mode: .truncate)
        XCTAssertEqual(lines, ["abc…"])
    }

    func testCharacterWrapping() {
        let lines = TextWrapping.wrap("abcdef", width: 2, mode: .character)
        XCTAssertEqual(lines, ["ab", "cd", "ef"])
    }

    func testCharacterWrappingKeepsWideCharactersIntact() {
        let lines = TextWrapping.wrap("あいう", width: 3, mode: .character)
        XCTAssertEqual(lines, ["あ", "い", "う"])
    }

    func testWordWrapping() {
        let lines = TextWrapping.wrap("the quick brown fox", width: 10, mode: .word)
        XCTAssertEqual(lines, ["the quick", "brown fox"])
    }

    func testWordWrappingBreaksOverlongWords() {
        let lines = TextWrapping.wrap("abcdefghij kl", width: 4, mode: .word)
        XCTAssertEqual(lines, ["abcd", "efgh", "ij", "kl"])
    }

    func testEmptyStringProducesOneEmptyLine() {
        XCTAssertEqual(TextWrapping.wrap("", width: 10, mode: .word), [""])
    }
}
