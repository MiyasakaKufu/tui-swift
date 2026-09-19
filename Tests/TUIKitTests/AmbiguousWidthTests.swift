#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import XCTest
@testable import TUIKit

final class AmbiguousWidthTests: XCTestCase {

    private var savedAmbiguousWidth: DisplayWidth.AmbiguousWidth = .narrow

    override func setUp() {
        super.setUp()
        savedAmbiguousWidth = DisplayWidth.ambiguousWidth
        DisplayWidth.ambiguousWidth = .narrow
    }

    override func tearDown() {
        DisplayWidth.ambiguousWidth = savedAmbiguousWidth
        super.tearDown()
    }

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    // MARK: - 幅の計算

    func testAmbiguousCharactersAreNarrowByDefault() {
        XCTAssertEqual(DisplayWidth.width(of: "─"), 1)
        XCTAssertEqual(DisplayWidth.width(of: "╭"), 1)
        XCTAssertEqual(DisplayWidth.width(of: "…"), 1)
        XCTAssertEqual(DisplayWidth.width(of: "█"), 1)
        XCTAssertEqual(DisplayWidth.width(of: "↑"), 1)
    }

    func testAmbiguousCharactersAreWideWhenConfigured() {
        DisplayWidth.ambiguousWidth = .wide
        XCTAssertEqual(DisplayWidth.width(of: "─"), 2)
        XCTAssertEqual(DisplayWidth.width(of: "╭"), 2)
        XCTAssertEqual(DisplayWidth.width(of: "…"), 2)
        XCTAssertEqual(DisplayWidth.width(of: "█"), 2)
        XCTAssertEqual(DisplayWidth.width(of: "↑"), 2)
    }

    func testPerCallSettingOverridesTheGlobalOne() {
        DisplayWidth.ambiguousWidth = .narrow
        XCTAssertEqual(DisplayWidth.width(of: "─", ambiguous: .wide), 2)

        DisplayWidth.ambiguousWidth = .wide
        XCTAssertEqual(DisplayWidth.width(of: "─", ambiguous: .narrow), 1)
    }

    func testStringWidthFollowsTheSetting() {
        XCTAssertEqual(DisplayWidth.width(of: "─a あ", ambiguous: .narrow), 5)
        XCTAssertEqual(DisplayWidth.width(of: "─a あ", ambiguous: .wide), 6)
    }

    func testASCIIAndFullWidthAreNotAffected() {
        XCTAssertEqual(DisplayWidth.width(of: "hello", ambiguous: .wide), 5)
        XCTAssertEqual(DisplayWidth.width(of: "日本語", ambiguous: .wide), 6)
        XCTAssertEqual(DisplayWidth.width(of: "🎉", ambiguous: .wide), 2)
    }

    func testZeroWidthCharactersStayZero() {
        // U+0300〜U+036F は Ambiguous でもあるが、結合文字の 0 桁が優先される。
        XCTAssertEqual(DisplayWidth.width(of: "e\u{0301}", ambiguous: .wide), 1)
        XCTAssertEqual(DisplayWidth.width(of: "\u{07}", ambiguous: .wide), 0)
    }

    func testPrefixFollowsTheSetting() {
        XCTAssertEqual(String(DisplayWidth.prefix(of: "───", width: 3, ambiguous: .narrow)), "───")
        XCTAssertEqual(String(DisplayWidth.prefix(of: "───", width: 3, ambiguous: .wide)), "─")
    }

    func testTruncateCountsTheEllipsisWithTheSetting() {
        XCTAssertEqual(DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .narrow), "abcd…")
        XCTAssertEqual(DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .wide), "abc…")
        XCTAssertEqual(
            DisplayWidth.width(of: DisplayWidth.truncate("abcdefgh", to: 5, ambiguous: .wide), ambiguous: .wide),
            5
        )
    }

    func testRangeTablesAreSortedAndDisjoint() {
        for ranges in [DisplayWidth.wideRanges, DisplayWidth.ambiguousRanges] {
            for (previous, next) in zip(ranges, ranges.dropFirst()) {
                XCTAssertLessThan(previous.upperBound, next.lowerBound)
            }
        }
    }

    // MARK: - 設定の解決

    func testEnvironmentValueParsing() {
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "1"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "0"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(environmentValue: "true"), .narrow)
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(environmentValue: ""))
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(environmentValue: nil))
    }

    func testLocaleValueParsing() {
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ja_JP.UTF-8"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "zh_CN.utf8"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ko_KR.UTF-8@euro"), .wide)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "en_US.UTF-8"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "ja_JP.eucJP"), .narrow)
        XCTAssertEqual(DisplayWidth.parseAmbiguousWidth(localeValue: "C"), .narrow)
        XCTAssertNil(DisplayWidth.parseAmbiguousWidth(localeValue: nil))
    }

    func testEnvironmentVariableOverridesTheResolvedSetting() {
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

    // MARK: - 描画側の切り替え

    func testBorderStyleReportsWhetherItFitsInSingleColumn() {
        XCTAssertTrue(BorderStyle.rounded.fitsInSingleColumn)
        XCTAssertTrue(BorderStyle.ascii.fitsInSingleColumn)

        DisplayWidth.ambiguousWidth = .wide
        XCTAssertFalse(BorderStyle.rounded.fitsInSingleColumn)
        XCTAssertTrue(BorderStyle.ascii.fitsInSingleColumn)
    }

    func testBorderFallsBackToASCIIWhenAmbiguousIsWide() {
        let view = Text("ab").border(.rounded)
        XCTAssertEqual(render(view, width: 4, height: 3), "╭──╮\n│ab│\n╰──╯")

        DisplayWidth.ambiguousWidth = .wide
        XCTAssertEqual(render(view, width: 4, height: 3), "+--+\n|ab|\n+--+")
    }

    func testProgressBarKeepsRowWidthWhenAmbiguousIsWide() {
        XCTAssertEqual(render(ProgressBar(value: 0.5), width: 10, height: 1), "█████░░░░░")

        DisplayWidth.ambiguousWidth = .wide
        // `█` は Ambiguous、`░`（U+2591）は Neutral なので、埋まる側だけ 2 桁になる。
        XCTAssertEqual(render(ProgressBar(value: 0.5), width: 10, height: 1), "██ ░░░░░")
    }
}
