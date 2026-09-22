import XCTest
@testable import TUIKit

@MainActor
final class TabExpansionTests: XCTestCase {

    func testTabExpandsToNextTabStop() async {
        XCTAssertEqual(TabExpansion.expand("a\tb", tabSize: 4), "a   b")
        XCTAssertEqual(TabExpansion.expand("abc\td", tabSize: 4), "abc d")
    }

    func testTabOnTabStopAdvancesFullWidth() async {
        XCTAssertEqual(TabExpansion.expand("abcd\te", tabSize: 4), "abcd    e")
        XCTAssertEqual(TabExpansion.expand("\ta", tabSize: 4), "    a")
    }

    func testConsecutiveTabs() async {
        XCTAssertEqual(TabExpansion.expand("a\t\tb", tabSize: 4), "a       b")
    }

    func testWideCharactersCountAsTwoColumns() async {
        XCTAssertEqual(TabExpansion.expand("あ\tb", tabSize: 4), "あ  b")
        XCTAssertEqual(TabExpansion.expand("あい\tb", tabSize: 4), "あい    b")
    }

    func testColumnResetsAtNewline() async {
        XCTAssertEqual(TabExpansion.expand("ab\tc\nd\te", tabSize: 4), "ab  c\nd   e")
    }

    func testStartColumnShiftsTabStops() async {
        XCTAssertEqual(TabExpansion.expand("\ta", tabSize: 4, startColumn: 1), "   a")
        // 3 桁目から始まるので "a" で 4 桁目（タブストップ上）に達し、タブは 4 桁進む。
        XCTAssertEqual(TabExpansion.expand("a\tb", tabSize: 4, startColumn: 3), "a    b")
    }

    func testZeroTabSizeRemovesTabs() async {
        XCTAssertEqual(TabExpansion.expand("a\tb", tabSize: 0), "ab")
    }

    func testTextWithoutTabsIsUnchanged() async {
        XCTAssertEqual(TabExpansion.expand("abc", tabSize: 4), "abc")
    }

    func testExpandedTextHasTheWidthItOccupies() async {
        let expanded = TabExpansion.expand("a\tb", tabSize: 8)
        XCTAssertEqual(expanded, "a       b")
        XCTAssertEqual(DisplayWidth.width(of: expanded), 9)
    }
}
