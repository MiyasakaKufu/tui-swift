import XCTest
@testable import TUIKit

@TUIActor
final class BufferTests: XCTestCase {

    func testWriteASCII() {
        var buffer = Buffer(size: Size(width: 5, height: 1))
        buffer.write("abc", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer.text(ofRow: 0), "abc  ")
    }

    /// タブの展開は文字の層（`TabExpansion`）の仕事で、セルの層では行わない。
    func testWriteDoesNotExpandTabs() {
        var buffer = Buffer(size: Size(width: 5, height: 1))
        let advanced = buffer.write("a\tb", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer.text(ofRow: 0), "ab   ")
        XCTAssertEqual(advanced, 2)
    }

    func testWriteClipsAtRightEdge() {
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("abcdef", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer.text(ofRow: 0), "abc")
    }

    func testWideCharacterOccupiesTwoCells() {
        var buffer = Buffer(size: Size(width: 6, height: 1))
        buffer.write("あい", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer[0, 0].character, "あ")
        XCTAssertTrue(buffer[1, 0].isContinuation)
        XCTAssertEqual(buffer[2, 0].character, "い")
        XCTAssertTrue(buffer[3, 0].isContinuation)
        XCTAssertEqual(buffer.text(ofRow: 0), "あい  ")
    }

    func testWideCharacterAtRightEdgeBecomesSpace() {
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("あああ", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer[0, 0].character, "あ")
        XCTAssertEqual(buffer[2, 0].character, " ")
        XCTAssertFalse(buffer[2, 0].isContinuation)
    }

    func testWriteRespectsClipRect() {
        var buffer = Buffer(size: Size(width: 8, height: 1))
        let clip = Rect(x: 2, y: 0, width: 3, height: 1)
        buffer.write("abcdefgh", at: Point(x: 0, y: 0), clippedTo: clip)
        XCTAssertEqual(buffer.text(ofRow: 0), "  cde   ")
    }

    func testWriteOutOfBoundsIsIgnored() {
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("abc", at: Point(x: 0, y: 5))
        XCTAssertEqual(buffer.text(ofRow: 0), "    ")
    }

    func testFillRect() {
        var buffer = Buffer(size: Size(width: 4, height: 2))
        buffer.fill(Rect(x: 1, y: 0, width: 2, height: 2), with: Cell(character: "#"))
        XCTAssertEqual(buffer.debugText(), " ## \n ## ")
    }

    func testSubscriptOutOfRangeReturnsEmptyCell() {
        let buffer = Buffer(size: Size(width: 2, height: 2))
        XCTAssertEqual(buffer[10, 10], Cell.empty)
    }

    func testResizeClearsContents() {
        var buffer = Buffer(size: Size(width: 2, height: 1))
        buffer.write("ab", at: .zero)
        buffer.resize(to: Size(width: 3, height: 1))
        XCTAssertEqual(buffer.text(ofRow: 0), "   ")
    }

    func testWriteStopsAtCRLF() {
        var buffer = Buffer(size: Size(width: 5, height: 1))
        buffer.write("ab\r\ncd", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer.text(ofRow: 0), "ab   ")
    }

    func testWriteStopsAtLoneCarriageReturn() {
        var buffer = Buffer(size: Size(width: 5, height: 1))
        buffer.write("ab\rcd", at: Point(x: 0, y: 0))
        XCTAssertEqual(buffer.text(ofRow: 0), "ab   ")
    }

    func testWriteLinesWithAlignment() {
        var buffer = Buffer(size: Size(width: 7, height: 2))
        let bounds = buffer.bounds
        buffer.write(lines: ["ab", "c"], in: bounds, alignment: .center)
        XCTAssertEqual(buffer.text(ofRow: 0), "  ab   ")
        XCTAssertEqual(buffer.text(ofRow: 1), "   c   ")
    }
}
