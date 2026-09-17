import XCTest
@testable import TUIKit

final class InputParserTests: XCTestCase {

    private func events(_ bytes: [UInt8]) -> [InputEvent] {
        var parser = InputParser()
        return parser.feed(bytes)
    }

    private func bytes(_ text: String) -> [UInt8] {
        Array(text.utf8)
    }

    func testPlainCharacter() {
        XCTAssertEqual(events([0x61]), [.key(KeyEvent(.character("a")))])
    }

    func testEnterAndTabAndBackspace() {
        XCTAssertEqual(events([0x0D]), [.key(KeyEvent(.enter))])
        XCTAssertEqual(events([0x09]), [.key(KeyEvent(.tab))])
        XCTAssertEqual(events([0x7F]), [.key(KeyEvent(.backspace))])
    }

    func testControlCharacter() {
        XCTAssertEqual(events([0x03]), [.key(KeyEvent(.character("c"), modifiers: .control))])
    }

    func testArrowKeys() {
        XCTAssertEqual(events(bytes("\u{1B}[A")), [.key(KeyEvent(.up))])
        XCTAssertEqual(events(bytes("\u{1B}[B")), [.key(KeyEvent(.down))])
        XCTAssertEqual(events(bytes("\u{1B}[C")), [.key(KeyEvent(.right))])
        XCTAssertEqual(events(bytes("\u{1B}[D")), [.key(KeyEvent(.left))])
    }

    func testArrowKeyWithModifier() {
        XCTAssertEqual(
            events(bytes("\u{1B}[1;5D")),
            [.key(KeyEvent(.left, modifiers: .control))]
        )
    }

    func testFunctionKeysFromSS3() {
        XCTAssertEqual(events(bytes("\u{1B}OP")), [.key(KeyEvent(.function(1)))])
    }

    func testFunctionKeyFromTildeSequence() {
        XCTAssertEqual(events(bytes("\u{1B}[15~")), [.key(KeyEvent(.function(5)))])
    }

    func testNavigationKeys() {
        XCTAssertEqual(events(bytes("\u{1B}[3~")), [.key(KeyEvent(.delete))])
        XCTAssertEqual(events(bytes("\u{1B}[5~")), [.key(KeyEvent(.pageUp))])
        XCTAssertEqual(events(bytes("\u{1B}[6~")), [.key(KeyEvent(.pageDown))])
        XCTAssertEqual(events(bytes("\u{1B}[H")), [.key(KeyEvent(.home))])
        XCTAssertEqual(events(bytes("\u{1B}[F")), [.key(KeyEvent(.end))])
    }

    func testShiftTab() {
        XCTAssertEqual(events(bytes("\u{1B}[Z")), [.key(KeyEvent(.backTab))])
    }

    func testAltCharacter() {
        XCTAssertEqual(
            events(bytes("\u{1B}a")),
            [.key(KeyEvent(.character("a"), modifiers: .alt))]
        )
    }

    func testLoneEscapeNeedsFlush() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed([0x1B]).isEmpty)
        XCTAssertTrue(parser.hasPendingBytes)
        XCTAssertEqual(parser.flush(), [.key(KeyEvent(.escape))])
        XCTAssertFalse(parser.hasPendingBytes)
    }

    func testIncompleteSequenceIsBuffered() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed([0x1B, 0x5B]).isEmpty)
        XCTAssertEqual(parser.feed([0x41]), [.key(KeyEvent(.up))])
    }

    func testMultiByteCharacterSplitAcrossReads() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed([0xE3]).isEmpty)
        XCTAssertEqual(parser.feed([0x81, 0x82]), [.key(KeyEvent(.character("あ")))])
    }

    func testMultipleEventsInOneChunk() {
        XCTAssertEqual(
            events(bytes("ab")),
            [.key(KeyEvent(.character("a"))), .key(KeyEvent(.character("b")))]
        )
    }

    func testMousePress() {
        let result = events(bytes("\u{1B}[<0;10;5M"))
        XCTAssertEqual(result, [
            .mouse(MouseEvent(position: Point(x: 9, y: 4), button: .left, action: .press))
        ])
    }

    func testMouseRelease() {
        let result = events(bytes("\u{1B}[<0;1;1m"))
        XCTAssertEqual(result, [
            .mouse(MouseEvent(position: Point(x: 0, y: 0), button: .left, action: .release))
        ])
    }

    func testMouseScroll() {
        let result = events(bytes("\u{1B}[<64;3;4M"))
        XCTAssertEqual(result, [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollUp))
        ])
    }

    func testBracketedPaste() {
        XCTAssertEqual(
            events(bytes("\u{1B}[200~hi\u{1B}[201~")),
            [.paste("hi")]
        )
    }

    func testBracketedPasteSplitAcrossReads() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed(bytes("\u{1B}[200~he")).isEmpty)
        XCTAssertEqual(parser.feed(bytes("llo\u{1B}[201~")), [.paste("hello")])
    }

    func testFocusEvents() {
        XCTAssertEqual(events(bytes("\u{1B}[I")), [.focus(true)])
        XCTAssertEqual(events(bytes("\u{1B}[O")), [.focus(false)])
    }
}
