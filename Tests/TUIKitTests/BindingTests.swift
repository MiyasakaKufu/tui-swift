import XCTest
@testable import TUIKit

@MainActor
final class BindingTests: XCTestCase {

    /// アプリの側で値を持つモデル。書き戻された回数も数える。
    private final class Model {
        var name = "" { didSet { nameWrites += 1 } }
        var selection = 0 { didSet { selectionWrites += 1 } }
        var nameWrites = 0
        var selectionWrites = 0
    }

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.renderAsRoot(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    private func key(_ key: Key) -> InputEvent {
        .key(KeyEvent(key))
    }

    // MARK: - Binding

    func testBindingReadsAndWritesThroughClosures() async {
        var stored = 1
        let binding = Binding(get: { stored }, set: { stored = $0 })
        XCTAssertEqual(binding.wrappedValue, 1)
        binding.wrappedValue = 2
        XCTAssertEqual(stored, 2)
    }

    func testBindingReadsAndWritesThroughKeyPath() async {
        let model = Model()
        let binding = Binding(model, \.name)
        binding.wrappedValue = "abc"
        XCTAssertEqual(model.name, "abc")
        model.name = "xyz"
        XCTAssertEqual(binding.wrappedValue, "xyz")
    }

    func testConstantBindingIgnoresWrites() async {
        let binding = Binding.constant(3)
        binding.wrappedValue = 4
        XCTAssertEqual(binding.wrappedValue, 3)
    }

    // MARK: - TextField

    func testTextFieldEditsAppValue() async {
        let model = Model()
        let state = TextFieldState()
        _ = TextField(text: Binding(model, \.name), state: state)

        XCTAssertTrue(state.handle(key(.character("a"))))
        XCTAssertTrue(state.handle(.paste("bc")))
        XCTAssertEqual(model.name, "abc")
        XCTAssertTrue(state.handle(key(.backspace)))
        XCTAssertEqual(model.name, "ab")
    }

    func testTextFieldShowsValueChangedByApp() async {
        let model = Model()
        let state = TextFieldState()
        let field = TextField(text: Binding(model, \.name), state: state, showsCursor: false)
        model.name = "hi"
        XCTAssertEqual(render(field, width: 4, height: 1), "hi  ")
    }

    func testTextFieldCursorFollowsValueShortenedByApp() async {
        let model = Model()
        model.name = "hello"
        let state = TextFieldState()
        _ = TextField(text: Binding(model, \.name), state: state)
        state.moveToEnd()
        XCTAssertEqual(state.cursor, 5)

        model.name = ""
        XCTAssertEqual(state.cursor, 0)
        state.insert("x")
        XCTAssertEqual(model.name, "x")
    }

    func testTextFieldDoesNotWriteBackWhileRendering() async {
        let model = Model()
        model.name = "a\tb"
        model.nameWrites = 0
        let state = TextFieldState()
        let field = TextField(text: Binding(model, \.name), state: state)

        _ = field.sizeThatFitsAsRoot(Size(width: 5, height: 1))
        _ = render(field, width: 5, height: 1)
        XCTAssertEqual(model.nameWrites, 0)
        XCTAssertEqual(model.name, "a\tb")
    }

    func testTextFieldDoesNotWriteBackWhenNothingChanges() async {
        let model = Model()
        model.name = "ab"
        model.nameWrites = 0
        let state = TextFieldState()
        _ = TextField(text: Binding(model, \.name), state: state)

        XCTAssertTrue(state.handle(key(.left)))
        XCTAssertTrue(state.handle(key(.home)))
        state.deleteToStart()
        XCTAssertEqual(model.nameWrites, 0)
    }

    // MARK: - ListView

    func testListViewMovesAppSelection() async {
        let model = Model()
        let state = ListState()
        _ = ListView(items: ["a", "b", "c"], selection: Binding(model, \.selection), state: state)

        XCTAssertTrue(state.handle(key(.down)))
        XCTAssertTrue(state.handle(key(.down)))
        XCTAssertEqual(model.selection, 2)
        XCTAssertTrue(state.handle(key(.down)))
        XCTAssertEqual(model.selection, 2, "末尾で止まること")
    }

    func testListViewScrollsToSelectionChangedByApp() async {
        let model = Model()
        let state = ListState()
        let items = ["a", "b", "c", "d"]
        let binding = Binding(model, \.selection)
        XCTAssertEqual(render(ListView(items: items, selection: binding, state: state), width: 5, height: 2), "> a  \n  b  ")

        model.selection = 3
        XCTAssertEqual(render(ListView(items: items, selection: binding, state: state), width: 5, height: 2), "  c  \n> d  ")
    }

    func testListViewDoesNotWriteBackWhileRendering() async {
        let model = Model()
        model.selection = 10
        model.selectionWrites = 0
        let state = ListState()
        let list = ListView(items: ["a", "b"], selection: Binding(model, \.selection), state: state)

        XCTAssertEqual(state.selectedIndex, 1, "範囲外の値は端へ丸めて読むこと")
        _ = list.sizeThatFitsAsRoot(Size(width: 5, height: 2))
        XCTAssertEqual(render(list, width: 5, height: 2), "  a  \n> b  ")
        XCTAssertEqual(model.selectionWrites, 0)
        XCTAssertEqual(model.selection, 10)
    }

    func testListViewDoesNotWriteBackWhenSelectionStays() async {
        let model = Model()
        let state = ListState()
        _ = ListView(items: ["a", "b"], selection: Binding(model, \.selection), state: state)

        XCTAssertTrue(state.handle(key(.up)))
        XCTAssertEqual(model.selectionWrites, 0)
    }
}
