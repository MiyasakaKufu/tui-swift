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
        XCTAssertTrue(state.handle(.paste("xy\nz")))
        XCTAssertEqual(state.text, "xyz")
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
}
