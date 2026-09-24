#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import XCTest
@testable import TUIKit

@MainActor
final class AmbiguousWidthTests: XCTestCase {

    private func render(
        _ view: any View,
        width: Int,
        height: Int,
        ambiguous: DisplayWidth.AmbiguousWidth
    ) -> String {
        var buffer = Buffer(size: Size(width: width, height: height), ambiguousWidth: ambiguous)
        let bounds = buffer.bounds
        view.renderAsRoot(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    // MARK: - 幅の計算

    func testAmbiguousCharactersAreNarrowWhenNarrow() async {
        for character: Character in ["─", "╭", "…", "█", "↑"] {
            XCTAssertEqual(DisplayWidth.width(of: character, ambiguous: .narrow), 1)
        }
    }

    func testAmbiguousCharactersAreWideWhenWide() async {
        for character: Character in ["─", "╭", "…", "█", "↑"] {
            XCTAssertEqual(DisplayWidth.width(of: character, ambiguous: .wide), 2)
        }
    }

    func testOmittedSettingFollowsTheDefault() async {
        let expected = DisplayWidth.width(of: "─", ambiguous: DisplayWidth.defaultAmbiguousWidth)
        XCTAssertEqual(DisplayWidth.width(of: "─"), expected)
    }

    func testStringWidthFollowsTheSetting() async {
        XCTAssertEqual(DisplayWidth.width(of: "─a あ", ambiguous: .narrow), 5)
        XCTAssertEqual(DisplayWidth.width(of: "─a あ", ambiguous: .wide), 6)
    }

    func testASCIIAndFullWidthAreNotAffected() async {
        XCTAssertEqual(DisplayWidth.width(of: "hello", ambiguous: .wide), 5)
        XCTAssertEqual(DisplayWidth.width(of: "日本語", ambiguous: .wide), 6)
        XCTAssertEqual(DisplayWidth.width(of: "🎉", ambiguous: .wide), 2)
    }

    /// Ambiguous でもある結合文字は、曖昧幅の設定に関わらず 0 桁になる。
    func testZeroWidthCharactersStayZero() async {
        let combiningAcuteAccent = "\u{0301}"
        XCTAssertEqual(DisplayWidth.width(of: "e" + combiningAcuteAccent, ambiguous: .wide), 1)
        XCTAssertEqual(DisplayWidth.width(of: "\u{07}", ambiguous: .wide), 0)
    }

    func testPrefixFollowsTheSetting() async {
        XCTAssertEqual(String(DisplayWidth.prefix(of: "───", width: 3, ambiguous: .narrow)), "───")
        XCTAssertEqual(String(DisplayWidth.prefix(of: "───", width: 3, ambiguous: .wide)), "─")
    }

    func testTruncateCountsTheEllipsisWithTheSetting() async {
        XCTAssertEqual(DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .narrow), "abcd…")
        XCTAssertEqual(DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .wide), "abc…")
        XCTAssertEqual(
            DisplayWidth.width(of: DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .wide), ambiguous: .wide),
            5
        )
    }

    func testRangeTablesAreSortedAndDisjoint() async {
        for ranges in [DisplayWidth.wideRanges, DisplayWidth.ambiguousRanges] {
            for (previous, next) in zip(ranges, ranges.dropFirst()) {
                XCTAssertLessThan(previous.upperBound, next.lowerBound)
            }
        }
    }

    // MARK: - 設定の解決

    func testEnvironmentValueParsing() async {
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "1"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "0"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "true"), .narrow)
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(environmentValue: ""))
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(environmentValue: nil))
    }

    func testLocaleValueParsing() async {
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ja_JP.UTF-8"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "zh_CN.utf8"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ko_KR.UTF-8@euro"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "en_US.UTF-8"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ja_JP.eucJP"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "C"), .narrow)
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(localeValue: nil))
    }

    func testEnvironmentVariableOverridesTheResolvedSetting() async {
        let name = DisplayWidth.ambiguousWidthEnvironmentVariable
        let original = getenv(name).map { String(cString: $0) }
        defer {
            if let original {
                setenv(name, original, 1)
            } else {
                unsetenv(name)
            }
        }

        setenv(name, "1", 1)
        XCTAssertEqual(DisplayWidth.ambiguousWidthFromEnvironment(), .wide)
        XCTAssertEqual(DisplayWidth.resolveAmbiguousWidth(), .wide)

        setenv(name, "0", 1)
        XCTAssertEqual(DisplayWidth.ambiguousWidthFromEnvironment(), .narrow)
        XCTAssertEqual(DisplayWidth.resolveAmbiguousWidth(), .narrow)

        unsetenv(name)
        XCTAssertNil(DisplayWidth.ambiguousWidthFromEnvironment())
        XCTAssertEqual(DisplayWidth.resolveAmbiguousWidth(), .narrow)
    }

    func testApplicationOptionsDefaultsToTheResolvedSetting() async {
        XCTAssertEqual(ApplicationOptions().ambiguousWidth, DisplayWidth.defaultAmbiguousWidth)
        XCTAssertEqual(ApplicationOptions(ambiguousWidth: .wide).ambiguousWidth, .wide)
    }

    // MARK: - 描画側の切り替え

    func testChildContextsCarryTheSetting() async {
        let root = RenderContext(screen: Rect(x: 0, y: 0, width: 1, height: 1), ambiguousWidth: .wide)
        XCTAssertEqual(root.context(for: EmptyView(), index: 0).context(for: EmptyView(), index: 1).ambiguousWidth, .wide)
    }

    func testBufferPlacesAmbiguousCharactersBySetting() async {
        var narrow = Buffer(size: Size(width: 4, height: 1), ambiguousWidth: .narrow)
        XCTAssertEqual(narrow.write("→ab", at: Point(x: 0, y: 0)), 3)
        XCTAssertEqual(narrow.debugText(), "→ab ")

        var wide = Buffer(size: Size(width: 4, height: 1), ambiguousWidth: .wide)
        XCTAssertEqual(wide.write("→ab", at: Point(x: 0, y: 0)), 4)
        XCTAssertTrue(wide[1, 0].isContinuation)
        XCTAssertEqual(wide.debugText(), "→ab")
    }

    func testTextWrapsBySetting() async {
        let view = Text("ab…cd", wrap: .character)
        XCTAssertEqual(render(view, width: 3, height: 2, ambiguous: .narrow), "ab…\ncd ")
        XCTAssertEqual(render(view, width: 3, height: 2, ambiguous: .wide), "ab \n…c")
    }

    func testBorderStyleReportsWhetherItFitsInSingleColumn() async {
        XCTAssertTrue(BorderStyle.rounded.fitsInSingleColumn(ambiguous: .narrow))
        XCTAssertTrue(BorderStyle.ascii.fitsInSingleColumn(ambiguous: .narrow))

        XCTAssertFalse(BorderStyle.rounded.fitsInSingleColumn(ambiguous: .wide))
        XCTAssertTrue(BorderStyle.ascii.fitsInSingleColumn(ambiguous: .wide))
    }

    /// 枠線の文字組みは、作ったときの曖昧幅の既定値に左右されない。
    func testBorderStyleKeepsAmbiguousCharacters() async {
        let style = BorderStyle(
            topLeft: "╔", top: "═", topRight: "╗",
            left: "║", right: "║",
            bottomLeft: "╚", bottom: "═", bottomRight: "╝"
        )
        XCTAssertEqual(style.topLeft, "╔")
        XCTAssertEqual(style.top, "═")
    }

    func testBorderFallsBackToASCIIWhenAmbiguousIsWide() async {
        let view = Text("ab").border(.rounded)
        XCTAssertEqual(render(view, width: 4, height: 3, ambiguous: .narrow), "╭──╮\n│ab│\n╰──╯")
        XCTAssertEqual(render(view, width: 4, height: 3, ambiguous: .wide), "+--+\n|ab|\n+--+")
    }

    /// 曖昧幅が 2 桁のとき、埋まる側（Ambiguous の `█`）だけが 2 桁になり、
    /// 残りの側（Neutral の `░`）は 1 桁のまま行の幅が保たれる。
    func testProgressBarKeepsRowWidthWhenAmbiguousIsWide() async {
        let bar = ProgressBar(value: 0.5)
        XCTAssertEqual(render(bar, width: 10, height: 1, ambiguous: .narrow), "█████░░░░░")
        XCTAssertEqual(render(bar, width: 10, height: 1, ambiguous: .wide), "██ ░░░░░")
    }
}
