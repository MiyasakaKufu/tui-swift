import XCTest
@testable import TUIKit

@TUIActor
final class WidgetTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    // MARK: - ProgressBar

    func testProgressBarFillsHalf() async {
        let bar = ProgressBar(value: 0.5)
        XCTAssertEqual(render(bar, width: 10, height: 1), "█████░░░░░")
    }

    func testProgressBarClampsAboveTotal() async {
        let bar = ProgressBar(value: 5, total: 1)
        XCTAssertEqual(render(bar, width: 4, height: 1), "████")
    }

    func testProgressBarWithPercentage() async {
        let bar = ProgressBar(value: 0.5, showsPercentage: true)
        XCTAssertEqual(render(bar, width: 10, height: 1), "███░░░ 50%")
    }

    // MARK: - ListState

    /// 描画済みとみなせるリストの状態を作る。
    ///
    /// - Parameters:
    ///   - itemCount: 項目の総数。
    ///   - visibleRows: 一度に表示できる行数。
    ///   - width: 描画した矩形の桁数。
    /// - Returns: 原点から広げた矩形を描画済みとして持つ状態。
    private func listState(itemCount: Int, visibleRows: Int, width: Int = 10) -> ListState {
        let state = ListState(itemCount: itemCount)
        state.renderedRect = Rect(x: 0, y: 0, width: width, height: visibleRows)
        return state
    }

    func testListStateScrollsToKeepSelectionVisible() async {
        let state = listState(itemCount: 10, visibleRows: 3)
        for _ in 0..<4 { state.moveDown() }
        XCTAssertEqual(state.selectedIndex, 4)
        XCTAssertEqual(state.scrollOffset, 2)
    }

    func testListStateStopsAtBounds() async {
        let state = listState(itemCount: 3, visibleRows: 3)
        state.moveUp()
        XCTAssertEqual(state.selectedIndex, 0)
        state.moveDown(by: 10)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testListStateHandlesArrowKeys() async {
        let state = listState(itemCount: 3, visibleRows: 3)
        XCTAssertTrue(state.handle(.key(KeyEvent(.down))))
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertTrue(state.handle(.key(KeyEvent(.up))))
        XCTAssertEqual(state.selectedIndex, 0)
        XCTAssertFalse(state.handle(.key(KeyEvent(.enter))))
    }

    /// ホイールは選択ではなく表示位置を動かす。
    func testListStateScrollsViewportWithWheel() async {
        let state = listState(itemCount: 20, visibleRows: 5)
        let down = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollDown)
        XCTAssertTrue(state.handle(.mouse(down)))
        XCTAssertEqual(state.scrollOffset, state.wheelScrollRows)
        XCTAssertEqual(state.selectedIndex, 0, "選択は動かないこと")

        let up = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollUp)
        XCTAssertTrue(state.handle(.mouse(up)))
        XCTAssertEqual(state.scrollOffset, 0)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    /// 表示位置は項目の範囲に収まり、端を超えない。
    func testListStateWheelStopsAtBounds() async {
        let state = listState(itemCount: 8, visibleRows: 5)
        let down = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollDown)
        for _ in 0..<10 { XCTAssertTrue(state.handle(.mouse(down))) }
        XCTAssertEqual(state.scrollOffset, 3)

        let up = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollUp)
        for _ in 0..<10 { XCTAssertTrue(state.handle(.mouse(up))) }
        XCTAssertEqual(state.scrollOffset, 0)
    }

    /// リストの外（隣のペインなど）で起きたホイールは処理しない。
    func testListStateIgnoresWheelOutsideRenderedRect() async {
        let state = ListState(itemCount: 20)
        state.renderedRect = Rect(x: 2, y: 1, width: 5, height: 4)

        for position in [Point(x: 1, y: 2), Point(x: 7, y: 2), Point(x: 4, y: 0), Point(x: 4, y: 5)] {
            let event = MouseEvent(position: position, button: .none, action: .scrollDown)
            XCTAssertFalse(state.handle(.mouse(event)), "\(position) は範囲外")
            XCTAssertEqual(state.scrollOffset, 0)
        }

        let inside = MouseEvent(position: Point(x: 2, y: 1), button: .none, action: .scrollDown)
        XCTAssertTrue(state.handle(.mouse(inside)))
        XCTAssertEqual(state.scrollOffset, state.wheelScrollRows)
    }

    /// 一度も描画していない状態では、どこで起きたホイールも処理しない。
    func testListStateIgnoresWheelBeforeFirstRender() async {
        let state = ListState(itemCount: 20)
        let event = MouseEvent(position: .zero, button: .none, action: .scrollDown)
        XCTAssertFalse(state.handle(.mouse(event)))
        XCTAssertEqual(state.scrollOffset, 0)
    }

    /// 選択を動かすと、表示位置は選択を追いかけて戻る。
    func testListStateSelectionScrollsBackAfterWheel() async {
        let state = listState(itemCount: 20, visibleRows: 5)
        let down = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollDown)
        for _ in 0..<5 { state.handle(.mouse(down)) }
        XCTAssertEqual(state.scrollOffset, 10)

        state.moveDown()
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.scrollOffset, 1)
    }

    /// 縦方向のリストは横スクロールを扱わない（親に委ねる）。
    func testListStateDoesNotHandleHorizontalScroll() async {
        let state = listState(itemCount: 5, visibleRows: 5)
        for action in [MouseAction.scrollLeft, .scrollRight] {
            let event = MouseEvent(position: .zero, button: .none, action: action)
            XCTAssertFalse(state.handle(.mouse(event)), "\(action) は扱わないこと")
            XCTAssertEqual(state.selectedIndex, 0, "\(action) で選択が動かないこと")
            XCTAssertEqual(state.scrollOffset, 0, "\(action) で表示位置が動かないこと")
        }
    }

    /// トラックパッドで斜めに動かすと横スクロールのコードが混ざる。
    /// 縦のノッチ数ぶんだけ表示位置が動き、横スクロールは無視されること。
    func testListStateIgnoresHorizontalWheelInDiagonalStream() async {
        let state = listState(itemCount: 30, visibleRows: 5)

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
        XCTAssertEqual(state.scrollOffset, 3 * state.wheelScrollRows)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testListStateSelectsClickedItem() async {
        let state = listState(itemCount: 10, visibleRows: 4)
        let press = MouseEvent(position: Point(x: 3, y: 2), button: .left, action: .press)
        XCTAssertTrue(state.handle(.mouse(press)))
        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.scrollOffset, 0, "クリックで表示位置が動かないこと")
    }

    /// 矩形が原点から離れていても、その中での行の位置で項目が決まる。
    func testListStateSelectsClickedItemInOffsetRect() async {
        let state = ListState(itemCount: 10)
        state.renderedRect = Rect(x: 2, y: 1, width: 5, height: 4)
        let press = MouseEvent(position: Point(x: 2, y: 3), button: .left, action: .press)
        XCTAssertTrue(state.handle(.mouse(press)))
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testListStateSelectsClickedItemAfterWheelScroll() async {
        let state = listState(itemCount: 20, visibleRows: 5)
        let down = MouseEvent(position: Point(x: 1, y: 1), button: .none, action: .scrollDown)
        for _ in 0..<3 { XCTAssertTrue(state.handle(.mouse(down))) }
        XCTAssertEqual(state.scrollOffset, 6)

        let press = MouseEvent(position: Point(x: 1, y: 1), button: .left, action: .press)
        XCTAssertTrue(state.handle(.mouse(press)))
        XCTAssertEqual(state.selectedIndex, 7)
        XCTAssertEqual(state.scrollOffset, 6, "クリックで表示位置が動かないこと")
    }

    func testListStateIgnoresClickOnRowWithoutItem() async {
        let state = listState(itemCount: 2, visibleRows: 5)
        state.select(1)
        for y in 2..<5 {
            let press = MouseEvent(position: Point(x: 0, y: y), button: .left, action: .press)
            XCTAssertFalse(state.handle(.mouse(press)), "\(y) 行目に項目はない")
            XCTAssertEqual(state.selectedIndex, 1)
        }
    }

    func testListStateIgnoresClickOutsideRenderedRect() async {
        let state = ListState(itemCount: 20)
        state.renderedRect = Rect(x: 2, y: 1, width: 5, height: 4)

        for position in [Point(x: 1, y: 2), Point(x: 7, y: 2), Point(x: 4, y: 0), Point(x: 4, y: 5)] {
            let press = MouseEvent(position: position, button: .left, action: .press)
            XCTAssertFalse(state.handle(.mouse(press)), "\(position) は範囲外")
            XCTAssertEqual(state.selectedIndex, 0)
        }
    }

    func testListStateSelectsOnlyWithLeftButton() async {
        let state = listState(itemCount: 10, visibleRows: 4)
        for button in [MouseButton.middle, .right, .backward, .forward, .none] {
            let press = MouseEvent(position: Point(x: 0, y: 2), button: button, action: .press)
            XCTAssertFalse(state.handle(.mouse(press)), "\(button) で選択しないこと")
            XCTAssertEqual(state.selectedIndex, 0)
        }
    }

    func testListStateIgnoresReleaseAndDragAndMove() async {
        let state = listState(itemCount: 10, visibleRows: 4)
        for action in [MouseAction.release, .drag, .move] {
            let event = MouseEvent(position: Point(x: 0, y: 2), button: .left, action: action)
            XCTAssertFalse(state.handle(.mouse(event)), "\(action) は扱わないこと")
            XCTAssertEqual(state.selectedIndex, 0)
        }
    }

    /// 一度も描画していない状態では、どこで起きた押下も処理しない。
    func testListStateIgnoresClickBeforeFirstRender() async {
        let state = ListState(itemCount: 20)
        let press = MouseEvent(position: .zero, button: .left, action: .press)
        XCTAssertFalse(state.handle(.mouse(press)))
        XCTAssertEqual(state.selectedIndex, 0)
    }

    func testListViewRendersSelectionMarker() async {
        let state = ListState()
        let list = ListView(items: ["a", "b", "c"], state: state)
        XCTAssertEqual(render(list, width: 5, height: 2), "> a  \n  b  ")
    }

    func testListViewScrollsWithState() async {
        let state = ListState()
        let list = ListView(items: ["a", "b", "c"], state: state)
        state.select(2)
        XCTAssertEqual(render(list, width: 5, height: 2), "  b  \n> c  ")
    }

    /// 描画は選択を追いかけ直さないので、ホイールで動かした表示位置が残る。
    func testListViewKeepsWheelScrollAcrossRenders() async {
        let items = ["a", "b", "c", "d"]
        let state = ListState()
        _ = render(ListView(items: items, state: state), width: 5, height: 2)

        let down = MouseEvent(position: .zero, button: .none, action: .scrollDown)
        XCTAssertTrue(state.handle(.mouse(down)))
        XCTAssertEqual(state.scrollOffset, 2)

        // `ListView` は描画のたびに作られ、`itemCount` が代入し直される。
        // そこで表示位置が選択へ戻らないことを、本番と同じ形で確かめる。
        XCTAssertEqual(render(ListView(items: items, state: state), width: 5, height: 2), "  c  \n  d  ")
        XCTAssertEqual(state.scrollOffset, 2)
        XCTAssertEqual(state.selectedIndex, 0)
    }

    /// 表示できる行数が変わったときは、選択が見える位置へ戻る。
    func testListViewScrollsToSelectionWhenHeightChanges() async {
        let items = ["a", "b", "c", "d"]
        let state = ListState()
        let list = ListView(items: items, state: state)
        state.select(3)
        XCTAssertEqual(render(list, width: 5, height: 2), "  c  \n> d  ")

        let up = MouseEvent(position: .zero, button: .none, action: .scrollUp)
        XCTAssertTrue(state.handle(.mouse(up)))
        XCTAssertEqual(state.scrollOffset, 0)

        XCTAssertEqual(render(list, width: 5, height: 3), "  b  \n  c  \n> d  ")
    }

    /// クリックで選ばれる項目は、その行に描かれている項目と一致する。
    func testListViewMarksClickedRowAfterWheelScroll() async {
        let items = ["a", "b", "c", "d"]
        let state = ListState()
        _ = render(ListView(items: items, state: state), width: 5, height: 2)

        let down = MouseEvent(position: .zero, button: .none, action: .scrollDown)
        XCTAssertTrue(state.handle(.mouse(down)))

        let press = MouseEvent(position: Point(x: 1, y: 1), button: .left, action: .press)
        XCTAssertTrue(state.handle(.mouse(press)))
        XCTAssertEqual(state.selectedIndex, 3)
        XCTAssertEqual(render(ListView(items: items, state: state), width: 5, height: 2), "  c  \n> d  ")
    }

    // MARK: - TextFieldState

    func testTextFieldInsertAndDelete() async {
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

    func testTextFieldDeleteForward() async {
        let state = TextFieldState(text: "abc")
        state.moveToStart()
        state.deleteForward()
        XCTAssertEqual(state.text, "bc")
        XCTAssertEqual(state.cursor, 0)
    }

    func testTextFieldCursorStaysInRange() async {
        let state = TextFieldState(text: "ab")
        state.moveToStart()
        state.moveLeft()
        XCTAssertEqual(state.cursor, 0)
        state.moveToEnd()
        state.moveRight()
        XCTAssertEqual(state.cursor, 2)
    }

    func testTextFieldCursorColumnUsesDisplayWidth() async {
        let state = TextFieldState(text: "あい")
        state.moveToStart()
        state.moveRight()
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testTextFieldControlShortcuts() async {
        let state = TextFieldState(text: "hello")
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("a"), modifiers: .control))))
        XCTAssertEqual(state.cursor, 0)
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("e"), modifiers: .control))))
        XCTAssertEqual(state.cursor, 5)
        XCTAssertTrue(state.handle(.key(KeyEvent(.character("u"), modifiers: .control))))
        XCTAssertEqual(state.text, "")
    }

    func testTextFieldHandlesPaste() async {
        let state = TextFieldState()
        XCTAssertTrue(state.handle(.paste("xyz")))
        XCTAssertEqual(state.text, "xyz")
    }

    func testTextFieldPasteTurnsNewlinesIntoSpace() async {
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

    func testTextFieldPasteTurnsTabIntoSpace() async {
        let state = TextFieldState()
        state.handle(.paste("a\tb"))
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)
    }

    func testTextFieldPasteDropsOtherControlCharacters() async {
        let state = TextFieldState()
        state.handle(.paste("a\u{07}b\u{1B}c\u{7F}d\u{9B}e"))
        XCTAssertEqual(state.text, "abcde")
        XCTAssertEqual(state.cursor, 5)
    }

    func testTextFieldSanitizedTextKeepsCursorMovable() async {
        let state = TextFieldState()
        state.handle(.paste("a\r\nb"))
        state.moveToStart()
        state.moveRight()
        XCTAssertEqual(state.cursorColumn, 1)
        state.moveRight()
        XCTAssertEqual(state.cursorColumn, 2)
    }

    func testTextFieldInsertSanitizesControlCharacters() async {
        let state = TextFieldState()
        state.insert("a")
        state.insert("\n")
        state.insert("\u{07}")
        state.insert("b")
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)
    }

    func testTextFieldInitialTextAndSetTextAreSanitized() async {
        let state = TextFieldState(text: "a\tb")
        XCTAssertEqual(state.text, "a b")
        XCTAssertEqual(state.cursor, 3)

        state.setText("c\r\nd\u{07}")
        XCTAssertEqual(state.text, "c d")
        XCTAssertEqual(state.cursor, 3)
    }

    /// プレースホルダも入力文字と同じ規則で整える（タブは空白 1 個）。
    func testTextFieldPlaceholderIsSanitized() async {
        let field = TextField(state: TextFieldState(), placeholder: "a\tb", showsCursor: false)
        XCTAssertEqual(render(field, width: 5, height: 1), "a b  ")
    }

    // MARK: - TextFieldState と書記素クラスタ

    /// 🇯🇵（地域表示記号 2 つ）
    private let flagEmoji = "\u{1F1EF}\u{1F1F5}"
    /// 👨‍👩‍👧（ZWJ で 3 つを結合）
    private let familyEmoji = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
    /// 👍🏽（肌の色の修飾子付き）
    private let thumbsUpEmoji = "\u{1F44D}\u{1F3FD}"

    /// 端末から届いたバイト列をパーサ経由で入力欄に流し込む。
    ///
    /// - Parameters:
    ///   - text: 端末から届いたとみなす文字列。
    ///   - state: 流し込む先の入力欄。
    private func typeText(_ text: String, into state: TextFieldState) {
        // まとめて `feed` してはいけない。1 回の read に収まった場合しか試せなくなる。
        var parser = InputParser()
        for byte in Array(text.utf8) {
            for event in parser.feed([byte]) {
                state.handle(event)
            }
        }
    }

    func testTypedFlagEmojiIsDeletedAsOneCharacter() async {
        let state = TextFieldState()
        typeText(flagEmoji, into: state)
        XCTAssertEqual(state.text, flagEmoji)
        XCTAssertEqual(state.cursor, 1)

        XCTAssertTrue(state.deleteBackward())
        XCTAssertEqual(state.text, "")
        XCTAssertEqual(state.cursor, 0)
    }

    func testTypedZWJEmojiIsDeletedAsOneCharacter() async {
        let state = TextFieldState()
        typeText(familyEmoji, into: state)
        XCTAssertEqual(state.text, familyEmoji)
        XCTAssertEqual(state.cursor, 1)
        XCTAssertEqual(state.cursorColumn, 2)

        XCTAssertTrue(state.deleteBackward())
        XCTAssertEqual(state.text, "")
    }

    func testTypedSkinToneEmojiIsDeletedAsOneCharacter() async {
        let state = TextFieldState()
        typeText(thumbsUpEmoji, into: state)
        XCTAssertEqual(state.text, thumbsUpEmoji)
        XCTAssertEqual(state.cursor, 1)

        XCTAssertTrue(state.deleteBackward())
        XCTAssertEqual(state.text, "")
    }

    func testCursorDoesNotEnterTypedEmoji() async {
        let state = TextFieldState()
        typeText("a" + flagEmoji + "b", into: state)
        XCTAssertEqual(state.cursor, 3)

        state.moveLeft()
        state.moveLeft()
        XCTAssertEqual(state.cursor, 1)
        XCTAssertTrue(state.deleteForward())
        XCTAssertEqual(state.text, "ab")
        XCTAssertEqual(state.cursor, 1)
    }

    func testTypedEmojiIsInsertedBeforeExistingText() async {
        let state = TextFieldState(text: "あ")
        state.moveToStart()
        typeText(flagEmoji, into: state)
        XCTAssertEqual(state.text, flagEmoji + "あ")
        XCTAssertEqual(state.cursor, 1)
    }

    func testPastedEmojiIsOneCharacter() async {
        let state = TextFieldState()
        XCTAssertTrue(state.handle(.paste(flagEmoji + thumbsUpEmoji)))
        XCTAssertEqual(state.cursor, 2)

        XCTAssertTrue(state.deleteBackward())
        XCTAssertEqual(state.text, flagEmoji)
    }

    func testTextFieldRendersPlaceholder() async {
        let state = TextFieldState()
        let field = TextField(state: state, placeholder: "name", showsCursor: false)
        XCTAssertEqual(render(field, width: 6, height: 1), "name  ")
    }

    func testTextFieldScrollsWhenCursorPassesEdge() async {
        let state = TextFieldState(text: "abcdef")
        let field = TextField(state: state, showsCursor: false)
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 3)
        XCTAssertEqual(render(field, width: 4, height: 1), "def ")
    }

    func testScrolledTextFieldDoesNotShowHalfOfWideCharacter() async {
        let state = TextFieldState(text: "あいう")
        let field = TextField(state: state, showsCursor: false)
        // 必要なスクロール量は 3 桁だが、「い」の途中で切れないよう 4 桁へ切り上げる。
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 4)
        XCTAssertEqual(render(field, width: 4, height: 1), "う  ")
    }

    func testTextFieldScrollsToCharacterBoundaryWithMixedWidths() async {
        let state = TextFieldState(text: "aあbい")
        let field = TextField(state: state, showsCursor: false)
        XCTAssertEqual(field.scrollOffset(forWidth: 4), 3)
        XCTAssertEqual(render(field, width: 4, height: 1), "bい ")
    }

    func testTextFieldScrollOffsetAlwaysLandsOnCharacterBoundary() async {
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

    func testEmptyTextFieldShowsCursorOverPlaceholder() async {
        let field = TextField(state: TextFieldState(), placeholder: "入力")
        var buffer = Buffer(size: Size(width: 10, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertTrue(buffer[0, 0].style.attributes.contains(.reverse))
        XCTAssertEqual(buffer.debugText(), "入力      ")
    }

    func testEmptyTextFieldWithoutPlaceholderShowsCursor() async {
        let field = TextField(state: TextFieldState())
        var buffer = Buffer(size: Size(width: 4, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertTrue(buffer[0, 0].style.attributes.contains(.reverse))
    }

    func testPlaceholderHasNoCursorWhenCursorHidden() async {
        let field = TextField(state: TextFieldState(), placeholder: "name", showsCursor: false)
        var buffer = Buffer(size: Size(width: 6, height: 1))
        let bounds = buffer.bounds
        field.render(into: &buffer, rect: bounds)

        XCTAssertFalse(buffer[0, 0].style.attributes.contains(.reverse))
    }

    // MARK: - TextField が報告するカーソル位置

    private func renderedCursorPoint(
        of field: TextField,
        in rect: Rect,
        screen: Size = Size(width: 12, height: 4)
    ) -> Point? {
        var buffer = Buffer(size: screen)
        field.render(into: &buffer, rect: rect)
        return field.state.renderedCursorPoint
    }

    func testTextFieldReportsNoCursorPositionBeforeRender() async {
        XCTAssertNil(TextFieldState(text: "ab").renderedCursorPoint)
    }

    func testTextFieldReportsCursorPositionInScreenCoordinates() async {
        let state = TextFieldState(text: "あい")
        let field = TextField(state: state)
        let rect = Rect(x: 2, y: 1, width: 6, height: 1)

        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 6, y: 1))
    }

    func testScrolledTextFieldReportsCursorPositionInsideRect() async {
        let state = TextFieldState(text: "abcdef")
        let field = TextField(state: state)
        let rect = Rect(x: 1, y: 0, width: 4, height: 1)

        XCTAssertEqual(field.scrollOffset(forWidth: 4), 3)
        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 4, y: 0))
    }

    func testEmptyTextFieldReportsCursorPositionAtPlaceholderStart() async {
        let state = TextFieldState()
        let field = TextField(state: state, placeholder: "ここに入力")
        let rect = Rect(x: 3, y: 2, width: 5, height: 1)

        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 3, y: 2))
    }

    func testTextFieldReportsCursorPositionWithHiddenCursor() async {
        let state = TextFieldState(text: "ab")
        let field = TextField(state: state, showsCursor: false)
        let rect = Rect(x: 0, y: 0, width: 5, height: 1)

        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 2, y: 0))
    }

    func testTextFieldCursorPositionFollowsCursorMovement() async {
        let state = TextFieldState(text: "abc")
        let field = TextField(state: state, showsCursor: false)
        let rect = Rect(x: 4, y: 3, width: 5, height: 1)

        state.moveToStart()
        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 4, y: 3))

        state.moveRight()
        XCTAssertEqual(renderedCursorPoint(of: field, in: rect), Point(x: 5, y: 3))
    }

    func testTextFieldForgetsCursorPositionWhenItHasNoRoom() async {
        let state = TextFieldState(text: "ab")
        let field = TextField(state: state)

        XCTAssertNotNil(renderedCursorPoint(of: field, in: Rect(x: 0, y: 0, width: 5, height: 1)))
        XCTAssertNil(renderedCursorPoint(of: field, in: Rect(x: 0, y: 0, width: 0, height: 1)))
    }
}
