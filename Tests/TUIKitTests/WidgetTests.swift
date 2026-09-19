import XCTest
@testable import TUIKit

final class WidgetTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    // MARK: - ProgressBar

    func testProgressBarFillsHalf() {
        let bar = ProgressBar(value: 0.5)
        XCTAssertEqual(render(bar, width: 10, height: 1), "█████░░░░░")
    }

    func testProgressBarClampsAboveTotal() {
        let bar = ProgressBar(value: 5, total: 1)
        XCTAssertEqual(render(bar, width: 4, height: 1), "████")
    }

    func testProgressBarWithPercentage() {
        let bar = ProgressBar(value: 0.5, showsPercentage: true)
        XCTAssertEqual(render(bar, width: 10, height: 1), "███░░░ 50%")
    }

    // MARK: - ListState

    func testListStateScrollsToKeepSelectionVisible() {
        let state = ListState(itemCount: 10)
        state.visibleRows = 3
        for _ in 0..<4 { state.moveDown() }
        XCTAssertEqual(state.selectedIndex, 4)
        XCTAssertEqual(state.scrollOffset, 2)
    }

    func testListStateStopsAtBounds() {
        let state = ListState(itemCount: 3)
        state.visibleRows = 3
        state.moveUp()
        XCTAssertEqual(state.selectedIndex, 0)
        state.moveDown(by: 10)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testListStateHandlesArrowKeys() {
        let state = ListState(itemCount: 3)
        state.visibleRows = 3
        XCTAssertTrue(state.handle(.key(KeyEvent(.down))))
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertTrue(state.handle(.key(KeyEvent(.up))))
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertFalse(state.handle(.key(KeyEvent(.enter))))
    }

    func testListStateHandlesScrollWheel() {
        let state = ListState(itemCount: 5)
        state.visibleRows = 5
        let scroll = MouseEvent(position: .zero, button: .none, action: .scrollDown)
        XCTAssertTrue(state.handle(.mouse(scroll)))
        XCTAssertEqual(state.selectedIndex, 1)
    }

    /// 縦方向のリストは横スクロールを扱わない（親に委ねる）。
    func testListStateDoesNotHandleHorizontalScroll() {
        let state = ListState(itemCount: 5)
        state.visibleRows = 5
        for action in [MouseAction.scrollLeft, .scrollRight] {
            let event = MouseEvent(position: .zero, button: .none, action: action)
            XCTAssertFalse(state.handle(.mouse(event)), "\(action) は扱わないこと")
            XCTAssertEqual(state.selectedIndex, 0, "\(action) で選択が動かないこと")
        }
    }

    /// トラックパッドで斜めに動かすと横スクロールのコードが混ざる。
    /// 縦のノッチ数ぶんだけ選択が動き、横スクロールは無視されること。
    func testListStateIgnoresHorizontalWheelInDiagonalStream() {
        let state = ListState(itemCount: 10)
        state.visibleRows = 5

        var parser = InputParser()
        let stream = "\u{1B}[<65;1;1M"   // 下
            + "\u{1B}[<67;1;1M"          // 右（斜めの動きで混ざる）
            + "\u{1B}[<65;1;1M"          // 下
            + "\u{1B}[<66;1;1M"          // 左（斜めの動きで混ざる）
            + "\u{1B}[<65;1;1M"          // 下
        let events = parser.feed(Array(stream.utf8))
        XCTAssertEqual(events.count, 5)

        var handledCount = 0
        for event in events where state.handle(event) { handledCount += 1 }
        XCTAssertEqual(handledCount, 3, "縦の 3 ノッチだけが処理されること")
        XCTAssertEqual(state.selectedIndex, 3)
    }

    func testListViewRendersSelectionMarker() {
        let state = ListState()
        let list = ListView(items: ["a", "b", "c"], state: state)
        XCTAssertEqual(render(list, width: 5, height: 2), "> a  \n  b  ")
    }

    func testListViewScrollsWithState() {
        let state = ListState()
        let list = ListView(items: ["a", "b", "c"], state: state)
        state.visibleRows = 2
        state.select(2)
        XCTAssertEqual(render(list, width: 5, height: 2), "  b  \n> c  ")
    }

    // MARK: - TextFieldState

    func testTextFieldInsertAndDelete() {
        let state = TextFieldState()
        state.insert("a")
        state.insert("b")
        state.insert("c")
        XCTAssertEqual(state.text, "abc")
        XCTAssertEqual(state.cursor, 3)

        state.moveLeft()
        state.deleteBackward()
        XCTAssertEqual(state.text, "ac")
        XCTAssertEqual(state.cursor, 1)
    }

    func testTextFieldDeleteForward() {
        let state = TextFieldState(text: "abc")
        state.moveToStart()
        state.deleteForward()
        XCTAssertEqual(state.text, "bc")
        XCTAssertEqual(state.cursor, 0)
    }

    func testTextFieldCursorStaysInRange() {
        let state = TextFieldState(text: "ab")
        state.moveToStart()
        state.moveLeft()
        XCTAssertEqual(state.cursor, 0)
        state.moveToEnd()
        state.moveRight()
        XCTAssertEqual(state.cursor, 2)
    }

    func testTextFieldCursorColumnUsesDisplayWidth() {
        let state = TextFieldState(text: "あい")
        state.moveToStart()
        state.moveRight()
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testTextFieldControlShortcuts() {
        let state = TextFieldState(text: "hello")
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("a"), modifiers: .control))))
        XCTAssertEqual(state.cursor, 0)
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("e"), modifiers: .control))))
        XCTAssertEqual(state.cursor, 5)
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("u"), modifiers: .control))))
        XCTAssertEqual(state.text, "")
    }

    func testTextFieldHandlesPaste() {
        let state = TextFieldState()
        XCTAssertTrue(state.handle(.paste("xyz")))
        XCTAssertEqual(state.text, "xyz")
    }

    func testTextFieldPasteTurnsNewlinesIntoSpace() {
        let state = TextFieldState()
        state.handle(.paste("a\rb"))
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)

        let crlf = TextFieldState()
        crlf.handle(.paste("a\r\nb"))
        XCTAssertEqual(crlf.text, "a b")
        XCTAssertEqual(crlf.cursor, 3)

        let lf = TextFieldState()
        lf.handle(.paste("a\nb"))
        XCTAssertEqual(lf.text, "a b")
    }

    func testTextFieldPasteTurnsTabIntoSpace() {
        let state = TextFieldState()
        state.handle(.paste("a\tb"))
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)
    }

    func testTextFieldPasteDropsOtherControlCharacters() {
        let state = TextFieldState()
        state.handle(.paste("a\u{07}b\u{1B}c\u{7F}d\u{9B}e"))
        XCTAssertEqual(state.text, "abcde")
        XCTAssertEqual(state.cursor, 5)
    }

    func testTextFieldSanitizedTextKeepsCursorMovable() {
        let state = TextFieldState()
        state.handle(.paste("a\r\nb"))
        state.moveToStart()
        state.moveRight()
        XCTAssertEqual(state.cursorColumn, 1)
        state.moveRight()
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testTextFieldInsertSanitizesControlCharacters() {
        let state = TextFieldState()
        state.insert("a")
        state.insert("\n")
        state.insert("\u{07}")
        state.insert("b")
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)
    }

    func testTextFieldInitialTextAndSetTextAreSanitized() {
        let state = TextFieldState(text: "a\tb")
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)

        state.setText("c\r\nd\u{07}")
        XCTAssertEqual(state.text, "c d")
        XCTAssertEqual(state.cursor, 3)
    }

    /// プレースホルダも入力文字と同じ規則で整える（タブは空白 1 個）。
    func testTextFieldPlaceholderIsSanitized() {
        let field = TextField(state: TextFieldState(), placeholder: "a\tb", showsCursor: false)
        XCTAssertEqual(render(field, width: 5, height: 1), "a b  ")
    }

    func testTextFieldRendersPlaceholder() {
        let state = TextFieldState()
        let field = TextField(state: state, placeholder: "name", showsCursor: false)
        XCTAssertEqual(render(field, width: 6, height: 1), "name  ")
    }

    func testTextFieldScrollsWhenCursorPassesEdge() {
        let state = TextFieldState(text: "abcdef")
        let field = TextField(state: state, showsCursor: false)
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 3)
        XCTAssertEqual(render(field, width: 4, height: 1), "def ")
    }

    func testScrolledTextFieldDoesNotShowHalfOfWideCharacter() {
        let state = TextFieldState(text: "あいう")
        let field = TextField(state: state, showsCursor: false)
        // 必要なスクロール量は 3 桁だが、「い」の途中で切れないよう 4 桁へ切り上げる。
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 4)
        XCTAssertEqual(render(field, width: 4, height: 1), "う  ")
    }

    func testTextFieldScrollsToCharacterBoundaryWithMixedWidths() {
        let state = TextFieldState(text: "aあbい")
        let field = TextField(state: state, showsCursor: false)
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 3)
        XCTAssertEqual(render(field, width: 4, height: 1), "bい ")
    }

    func testTextFieldScrollOffsetAlwaysLandsOnCharacterBoundary() {
        let state = TextFieldState()
        let field = TextField(state: state, showsCursor: false)
        for character in "aあiい漢x字" {
            state.insert(character)
            for width in 1...6 {
                let offset = field.scrollOffset(forWidth: width)
                var boundaries: Set<Int> = [0]
                var column = 0
                for existing in state.text {
                    column += DisplayWidth.width(of: existing)
                    boundaries.insert(column)
                }
                XCTAssertTrue(
                    boundaries.contains(offset),
                    "幅 \(width)・内容 \(state.text) でスクロール量 \(offset) が文字の区切りにない"
                )
                XCTAssertLessThan(state.cursorColumn - offset, width)
            }
        }
    }

    func testEmptyTextFieldShowsCursorOverPlaceholder() {
        let field = TextField(state: TextFieldState(), placeholder: "入力")
        var buffer = Buffer(size: Size(width: 10, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertTrue(buffer[0, 0].style.attributes.contains(.reverse))
        XCTAssertEqual(buffer.debugText(), "入力      ")
    }

    func testEmptyTextFieldWithoutPlaceholderShowsCursor() {
        let field = TextField(state: TextFieldState())
        var buffer = Buffer(size: Size(width: 4, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertTrue(buffer[0, 0].style.attributes.contains(.reverse))
    }

    func testPlaceholderHasNoCursorWhenCursorHidden() {
        let field = TextField(state: TextFieldState(), placeholder: "name", showsCursor: false)
        var buffer = Buffer(size: Size(width: 6, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertFalse(buffer[0, 0].style.attributes.contains(.reverse))
    }
}
