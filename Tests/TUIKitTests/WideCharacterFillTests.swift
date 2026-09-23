import XCTest
@testable import TUIKit

/// 1 セルずつ書き込む描画に全角文字を渡しても、行の表示幅がバッファの幅を超えないことを確かめる。
@MainActor
final class WideCharacterFillTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> Buffer {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.renderAsRoot(into: &buffer, rect: bounds)
        return buffer
    }

    /// 各行の表示幅がバッファの幅と一致することを確かめる。
    private func assertRowsFit(_ buffer: Buffer, file: StaticString = #filePath, line: UInt = #line) {
        for y in 0..<buffer.size.height {
            XCTAssertEqual(
                DisplayWidth.width(of: buffer.text(ofRow: y)),
                buffer.size.width,
                "行 \(y) の表示幅",
                file: file,
                line: line
            )
        }
    }

    // MARK: - 再現

    func testWideCharacterInFillFitsBuffer() async {
        let buffer = render(Fill("あ"), width: 5, height: 2)
        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), "ああ ")
    }

    func testWideCharacterInDividerFitsBuffer() async {
        let buffer = render(Divider(character: "＝"), width: 5, height: 1)
        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), "＝＝ ")
    }

    func testWideCharacterInProgressBarFitsBuffer() async {
        let buffer = render(ProgressBar(value: 1, filledCharacter: "🟩"), width: 6, height: 1)
        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), "🟩🟩🟩")
    }

    func testWideCharacterInBorderStyleFitsBuffer() async {
        let wide = BorderStyle(
            topLeft: "┌", top: "＝", topRight: "┐",
            left: "｜", right: "｜",
            bottomLeft: "└", bottom: "＝", bottomRight: "┘"
        )
        let buffer = render(EmptyView().border(wide), width: 8, height: 3)
        assertRowsFit(buffer)
    }

    // MARK: - 奇数幅

    func testFillWithWideCharacterPadsOddWidth() async {
        var buffer = Buffer(size: Size(width: 7, height: 1))
        buffer.fill(buffer.bounds, repeating: "あ")
        XCTAssertEqual(buffer.text(ofRow: 0), "あああ ")
        XCTAssertEqual(buffer[6, 0].character, " ")
        XCTAssertFalse(buffer[6, 0].isContinuation)
        XCTAssertTrue(buffer[1, 0].isContinuation)
    }

    func testFillWithWideCharacterInOddOffsetRegion() async {
        var buffer = Buffer(size: Size(width: 6, height: 1))
        buffer.fill(Rect(x: 1, y: 0, width: 4, height: 1), repeating: "あ")
        XCTAssertEqual(buffer.text(ofRow: 0), " ああ ")
        XCTAssertEqual(buffer[1, 0].character, "あ")
        XCTAssertTrue(buffer[2, 0].isContinuation)
    }

    func testFillWithWideCharacterInSingleColumnBecomesSpace() async {
        var buffer = Buffer(size: Size(width: 1, height: 1))
        buffer.fill(buffer.bounds, repeating: "あ")
        XCTAssertEqual(buffer.text(ofRow: 0), " ")
    }

    func testProgressBarWithWideCharactersPadsOddSegments() async {
        // 幅 9 の 37.5% は 3 桁。全角文字は 1 個しか置けないので、残りの 1 桁は空白になる。
        let buffer = render(
            ProgressBar(value: 3, total: 8, filledCharacter: "＊", emptyCharacter: "・"),
            width: 9,
            height: 1
        )
        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), "＊ ・・・")
    }

    func testDividerWithZeroWidthCharacterBecomesSpaces() async {
        let buffer = render(Divider(character: "\u{0301}"), width: 3, height: 1)
        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), "   ")
    }

    // MARK: - 重ね書き

    func testOverwritingWideCharacterHeadBlanksContinuation() async {
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("あい", at: Point(x: 0, y: 0))
        buffer[0, 0] = Cell(character: "X")

        assertRowsFit(buffer)
        XCTAssertFalse(buffer[1, 0].isContinuation)
        XCTAssertEqual(buffer.text(ofRow: 0), "X い")
    }

    /// `TextField` は全角文字のセルへカーソルを重ねるとき、同じ文字を書き直す。
    func testOverwritingWideCharacterHeadWithWideCharacterKeepsContinuation() async {
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("あい", at: Point(x: 0, y: 0))
        buffer[0, 0] = Cell(character: "あ", style: Style(attributes: .reverse))

        assertRowsFit(buffer)
        XCTAssertTrue(buffer[1, 0].isContinuation)
        XCTAssertEqual(buffer.text(ofRow: 0), "あい")
    }

    func testOverwritingWideCharacterContinuationBlanksHead() async {
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("あい", at: Point(x: 0, y: 0))
        buffer[1, 0] = Cell(character: "X")

        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), " Xい")
    }

    func testFillOverlappingWideCharactersKeepsColumns() async {
        var buffer = Buffer(size: Size(width: 6, height: 1))
        buffer.write("あいう", at: Point(x: 0, y: 0))
        buffer.fill(Rect(x: 1, y: 0, width: 3, height: 1), with: Cell(character: "#"))

        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), " ###う")
    }

    func testBlankedHalfKeepsStyle() async {
        var buffer = Buffer(size: Size(width: 4, height: 1))
        let style = Style(background: .blue)
        buffer.write("あ", at: Point(x: 0, y: 0), style: style)
        buffer[0, 0] = Cell(character: "X")

        XCTAssertEqual(buffer[1, 0].style, style)
    }

    func testWritingWideCharacterOverWideCharacterKeepsColumns() async {
        var buffer = Buffer(size: Size(width: 6, height: 1))
        buffer.write("あいう", at: Point(x: 0, y: 0))
        buffer.write("か", at: Point(x: 1, y: 0))

        assertRowsFit(buffer)
        XCTAssertEqual(buffer.text(ofRow: 0), " か う")
    }

    // MARK: - BorderStyle の検証

    func testBorderStyleReplacesWideCharactersWithDefaults() async {
        let style = BorderStyle(
            topLeft: "＋", top: "＝", topRight: "＋",
            left: "｜", right: "｜",
            bottomLeft: "＋", bottom: "＝", bottomRight: "＋"
        )
        XCTAssertEqual(style.topLeft, "┌")
        XCTAssertEqual(style.top, "─")
        XCTAssertEqual(style.topRight, "┐")
        XCTAssertEqual(style.left, "│")
        XCTAssertEqual(style.right, "│")
        XCTAssertEqual(style.bottomLeft, "└")
        XCTAssertEqual(style.bottom, "─")
        XCTAssertEqual(style.bottomRight, "┘")
    }

    func testBorderStyleKeepsSingleWidthCharacters() async {
        XCTAssertEqual(BorderStyle.ascii.topLeft, "+")
        XCTAssertEqual(BorderStyle.ascii.top, "-")
        XCTAssertEqual(BorderStyle.ascii.left, "|")
        XCTAssertEqual(BorderStyle.double.top, "═")
    }
}
