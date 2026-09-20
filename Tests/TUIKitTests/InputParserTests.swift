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

    func testFunctionKeysOneToFourWithModifiers() {
        XCTAssertEqual(
            events(bytes("\u{1B}[1;2P")),
            [.key(KeyEvent(.function(1), modifiers: .shift))]
        )
        XCTAssertEqual(
            events(bytes("\u{1B}[1;3Q")),
            [.key(KeyEvent(.function(2), modifiers: .alt))]
        )
        XCTAssertEqual(
            events(bytes("\u{1B}[1;5R")),
            [.key(KeyEvent(.function(3), modifiers: .control))]
        )
        XCTAssertEqual(
            events(bytes("\u{1B}[1;5S")),
            [.key(KeyEvent(.function(4), modifiers: .control))]
        )
        XCTAssertEqual(
            events(bytes("\u{1B}[1;8P")),
            [.key(KeyEvent(.function(1), modifiers: [.shift, .alt, .control]))]
        )
    }

    /// 修飾パラメータのない `CSI P`〜`CSI S` も F1〜F4 として扱う。
    func testFunctionKeysOneToFourWithoutModifiers() {
        XCTAssertEqual(events(bytes("\u{1B}[P")), [.key(KeyEvent(.function(1)))])
        XCTAssertEqual(events(bytes("\u{1B}[S")), [.key(KeyEvent(.function(4)))])
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

    func testTimedOutBracketAndOBecomeAltKeys() {
        for (text, character) in [("\u{1B}[", Character("[")), ("\u{1B}O", Character("O"))] {
            var parser = InputParser()
            XCTAssertTrue(parser.feed(bytes(text)).isEmpty)
            XCTAssertEqual(
                parser.flush(),
                [.key(KeyEvent(.character(character), modifiers: .alt))]
            )
            XCTAssertFalse(parser.hasPendingBytes)
        }
    }

    func testTimedOutHalfSequenceIsDiscarded() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed(bytes("\u{1B}[<65;10")).isEmpty)
        XCTAssertEqual(parser.flush(), [])
        XCTAssertFalse(parser.hasPendingBytes)
    }

    func testSequenceSplitMidwayIsParsedWhenTheRestArrives() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed(bytes("\u{1B}[<65;10")).isEmpty)
        XCTAssertEqual(parser.feed(bytes(";5M")), [
            .mouse(MouseEvent(position: Point(x: 9, y: 4), button: .none, action: .scrollDown))
        ])
    }

    func testStartedSequenceIsWaitedForLongerThanLoneEscape() {
        var parser = InputParser()
        XCTAssertNil(parser.pendingWaitDuration)

        XCTAssertTrue(parser.feed([0x1B]).isEmpty)
        let escapeDuration = parser.pendingWaitDuration
        XCTAssertTrue(parser.feed([0x5B]).isEmpty)
        let sequenceDuration = parser.pendingWaitDuration

        XCTAssertNotNil(escapeDuration)
        XCTAssertNotNil(sequenceDuration)
        XCTAssertLessThan(escapeDuration ?? 0, sequenceDuration ?? 0)
    }

    func testPasteIsNotWaitedFor() {
        var parser = InputParser()
        XCTAssertTrue(parser.feed(bytes("\u{1B}[200~ab")).isEmpty)
        XCTAssertNil(parser.pendingWaitDuration)
        XCTAssertEqual(parser.flush(), [])
        XCTAssertEqual(parser.feed(bytes("\u{1B}[201~")), [.paste("ab")])
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

    func testMouseWheelFourDirections() {
        XCTAssertEqual(events(bytes("\u{1B}[<64;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollUp))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<65;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollDown))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<66;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollLeft))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<67;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollRight))
        ])
    }

    func testHorizontalWheelIsNotReportedAsVerticalScroll() {
        for text in ["\u{1B}[<66;10;5M", "\u{1B}[<67;10;5M"] {
            guard case .mouse(let mouseEvent)? = events(bytes(text)).first else {
                return XCTFail("マウスイベントが得られなかった: \(text)")
            }
            XCTAssertNotEqual(mouseEvent.action, .scrollUp)
            XCTAssertNotEqual(mouseEvent.action, .scrollDown)
        }
    }

    func testMouseWheelWithModifiers() {
        XCTAssertEqual(events(bytes("\u{1B}[<70;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .scrollLeft, modifiers: [.shift]))
        ])
    }

    func testMouseMove() {
        XCTAssertEqual(events(bytes("\u{1B}[<35;10;5M")), [
            .mouse(MouseEvent(position: Point(x: 9, y: 4), button: .none, action: .move))
        ])
    }

    func testMouseMoveWithModifiers() {
        XCTAssertEqual(events(bytes("\u{1B}[<39;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .none, action: .move, modifiers: [.shift]))
        ])
    }

    func testMoveWithButtonHeldIsReportedAsDrag() {
        XCTAssertEqual(events(bytes("\u{1B}[<32;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .left, action: .drag))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<34;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .right, action: .drag))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<160;3;4M")), [
            .mouse(MouseEvent(position: Point(x: 2, y: 3), button: .backward, action: .drag))
        ])
    }

    func testExtraMouseButtons() {
        XCTAssertEqual(events(bytes("\u{1B}[<128;1;1M")), [
            .mouse(MouseEvent(position: .zero, button: .backward, action: .press))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<129;1;1M")), [
            .mouse(MouseEvent(position: .zero, button: .forward, action: .press))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<130;1;1M")), [
            .mouse(MouseEvent(position: .zero, button: .button10, action: .press))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<131;1;1M")), [
            .mouse(MouseEvent(position: .zero, button: .button11, action: .press))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<128;1;1m")), [
            .mouse(MouseEvent(position: .zero, button: .backward, action: .release))
        ])
        XCTAssertEqual(events(bytes("\u{1B}[<160;2;2M")), [
            .mouse(MouseEvent(position: Point(x: 1, y: 1), button: .backward, action: .drag))
        ])
    }

    func testExtraMouseButtonsAreNotReportedAsPrimaryButtons() {
        for text in ["\u{1B}[<128;1;1M", "\u{1B}[<129;1;1M"] {
            guard case .mouse(let mouseEvent)? = events(bytes(text)).first else {
                return XCTFail("マウスイベントが得られなかった: \(text)")
            }
            XCTAssertNotEqual(mouseEvent.button, .left)
            XCTAssertNotEqual(mouseEvent.button, .middle)
            XCTAssertNotEqual(mouseEvent.button, .right)
        }
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

    // MARK: - kitty keyboard protocol

    /// `CSI u` 形式では、同じバイト列になっていたキーが別のキーとして届く。
    func testKeyboardProtocolDisambiguatesControlKeys() {
        XCTAssertEqual(
            events(bytes("\u{1B}[105;5u")),
            [.key(KeyEvent(.character("i"), modifiers: .control))]
        )
        XCTAssertEqual(events(bytes("\u{1B}[9u")), [.key(KeyEvent(.tab))])
        XCTAssertEqual(
            events(bytes("\u{1B}[109;5u")),
            [.key(KeyEvent(.character("m"), modifiers: .control))]
        )
        XCTAssertEqual(events(bytes("\u{1B}[13u")), [.key(KeyEvent(.enter))])
    }

    /// `CSI u` 形式の Escape・Backspace も、時間切れを待たずに確定する。
    func testKeyboardProtocolNamedKeys() {
        XCTAssertEqual(events(bytes("\u{1B}[27u")), [.key(KeyEvent(.escape))])
        XCTAssertEqual(events(bytes("\u{1B}[127u")), [.key(KeyEvent(.backspace))])
        XCTAssertEqual(
            events(bytes("\u{1B}[27;3u")),
            [.key(KeyEvent(.escape, modifiers: .alt))]
        )
    }

    /// Shift+Tab は、形式が変わっても `CSI Z` と同じキーになる。
    func testKeyboardProtocolShiftTabMatchesLegacyBackTab() {
        XCTAssertEqual(events(bytes("\u{1B}[9;2u")), events(bytes("\u{1B}[Z")))
        XCTAssertEqual(events(bytes("\u{1B}[9;2u")), [.key(KeyEvent(.backTab))])
        XCTAssertEqual(
            events(bytes("\u{1B}[9;6u")),
            [.key(KeyEvent(.backTab, modifiers: .control))]
        )
    }

    /// 私用領域のキーコードは、対応するキーが無ければ文字にしない。
    func testKeyboardProtocolFunctionalKeys() {
        XCTAssertEqual(events(bytes("\u{1B}[57376u")), [.key(KeyEvent(.function(13)))])
        XCTAssertEqual(events(bytes("\u{1B}[57399u")), [.key(KeyEvent(.character("0")))])
        XCTAssertEqual(events(bytes("\u{1B}[57414u")), [.key(KeyEvent(.enter))])
        XCTAssertEqual(events(bytes("\u{1B}[57417u")), [.key(KeyEvent(.left))])
        // 57358 は Caps Lock。
        XCTAssertEqual(events(bytes("\u{1B}[57358u")), [])
    }

    /// 下位パラメータ（`:`）は、上位のパラメータへ混ざらない。
    func testKeyboardProtocolSubParametersDoNotMergeIntoModifiers() {
        XCTAssertEqual(
            events(bytes("\u{1B}[97;2:1u")),
            [.key(KeyEvent(.character("a"), modifiers: .shift))]
        )
        // 下位パラメータを読み飛ばすと `2:1` が 21 になり、Ctrl が付いて見える。
        guard case .key(let keyEvent)? = events(bytes("\u{1B}[97;2:1u")).first else {
            return XCTFail("キーイベントが得られなかった")
        }
        XCTAssertFalse(keyEvent.modifiers.contains(.control))
    }

    /// 代替キーコード（`:`）が付いていても、先頭のキーコードで解釈する。
    func testKeyboardProtocolAlternateKeyCodesAreIgnored() {
        XCTAssertEqual(
            events(bytes("\u{1B}[97:65;2u")),
            [.key(KeyEvent(.character("a"), modifiers: .shift))]
        )
    }

    /// キーを離した通知は、押したときと同じキーを二重に届けない。
    func testKeyboardProtocolReleaseIsIgnored() {
        XCTAssertEqual(events(bytes("\u{1B}[97;1:3u")), [])
        XCTAssertEqual(events(bytes("\u{1B}[97;1:1u")), [.key(KeyEvent(.character("a")))])
        // 種別 2 はキーリピート。
        XCTAssertEqual(events(bytes("\u{1B}[97;1:2u")), [.key(KeyEvent(.character("a")))])
    }

    /// 対応状況の応答はキーではなく、応答として取り出せる。
    func testKeyboardProtocolReplyIsNotAKey() {
        var parser = InputParser()
        XCTAssertEqual(parser.feed(bytes("\u{1B}[?1u")), [])
        XCTAssertEqual(parser.takeReplies(), [.keyboardProtocol(flags: 1)])
        XCTAssertEqual(parser.takeReplies(), [])
    }

    /// 装置属性の応答はキーではなく、応答として取り出せる。
    func testDeviceAttributesReplyIsNotAKey() {
        var parser = InputParser()
        XCTAssertEqual(parser.feed(bytes("\u{1B}[?62;9;c")), [])
        XCTAssertEqual(parser.takeReplies(), [.deviceAttributes])
    }

    /// 応答とキーが続けて届いても、キーは失われない。
    func testRepliesAndKeysArriveTogether() {
        var parser = InputParser()
        XCTAssertEqual(
            parser.feed(bytes("\u{1B}[?1u\u{1B}[?62;ca")),
            [.key(KeyEvent(.character("a")))]
        )
        XCTAssertEqual(parser.takeReplies(), [.keyboardProtocol(flags: 1), .deviceAttributes])
    }
}
