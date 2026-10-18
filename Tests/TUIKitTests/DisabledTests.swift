import XCTest
@testable import TUIKit

/// 2 つ目の `TextField` だけを、`View.disabled(_:)` で `.key`・`.mouse` と Tab によるフォーカスの移動の対象から外せる `View`。
private struct LockableForm: View {
    enum Field: Hashable {
        case name
        case note
    }

    let nameState: TextFieldState
    let noteState: TextFieldState
    let isNoteLocked: Bool
    @FocusState var field: Field?

    var body: some View {
        VStack(spacing: 0) {
            TextField(state: nameState)
                .focused($field, equals: .name)
            TextField(state: noteState)
                .focused($field, equals: .note)
                .disabled(isNoteLocked)
        }
    }
}

@MainActor
final class DisabledTests: XCTestCase {
    private lazy var first = TextFieldState()
    private lazy var second = TextFieldState()
    private lazy var third = TextFieldState()

    // MARK: - フォーカスと Tab

    func testTabSkipsDisabledView() async {
        let harness = FocusHarness(size: Size(width: 10, height: 3)) {
            VStack(spacing: 0) {
                TextField(state: self.first)
                TextField(state: self.second).disabled(true)
                TextField(state: self.third)
            }
        }

        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.character("c"))
        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.character("a"))
        XCTAssertEqual(harness.press(.backTab), .handled)
        harness.press(.character("C"))

        XCTAssertEqual(first.text, "a")
        XCTAssertEqual(second.text, "")
        XCTAssertEqual(third.text, "cC")
    }

    func testFirstFocusSkipsDisabledView() async {
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            VStack(spacing: 0) {
                TextField(state: self.first).disabled(true)
                TextField(state: self.second)
            }
        }

        harness.press(.character("x"))

        XCTAssertEqual(first.text, "")
        XCTAssertEqual(second.text, "x")
    }

    func testDisablingFocusedViewMovesFocusToFirstAcceptingView() async {
        var isSecondDisabled = false
        let harness = FocusHarness(size: Size(width: 10, height: 3)) {
            VStack(spacing: 0) {
                TextField(state: self.first)
                TextField(state: self.second).disabled(isSecondDisabled)
                TextField(state: self.third)
            }
        }
        harness.press(.tab)

        isSecondDisabled = true
        harness.draw()
        harness.press(.character("q"))

        XCTAssertEqual(first.text, "q")
        XCTAssertEqual(second.text, "")
    }

    func testDisablingEveryTargetLeavesNoFocusAndReenablingDoesNotRestoreIt() async {
        var isFormDisabled = false
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            VStack(spacing: 0) {
                TextField(state: self.first)
                TextField(state: self.second)
            }
            .disabled(isFormDisabled)
        }
        harness.press(.tab)

        isFormDisabled = true
        harness.draw()

        XCTAssertNil(harness.press(.character("x")))
        XCTAssertNil(harness.press(.tab))
        XCTAssertFalse(harness.paste("p"))
        XCTAssertNil(harness.context.cursorPosition)
        XCTAssertEqual(first.text, "")
        XCTAssertEqual(second.text, "")

        isFormDisabled = false
        harness.draw()
        harness.press(.character("y"))

        XCTAssertEqual(first.text, "y")
        XCTAssertEqual(second.text, "")
    }

    func testOuterDisabledWinsOverInnerFalse() async {
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    TextField(state: self.first).disabled(false)
                }
                .disabled(true)
                TextField(state: self.second)
            }
        }

        harness.press(.tab)
        XCTAssertFalse(harness.click(at: Point(x: 0, y: 0)))
        harness.press(.character("z"))

        XCTAssertEqual(first.text, "")
        XCTAssertEqual(second.text, "z")
        XCTAssertTrue(harness.buffer[0, 0].style.attributes.contains(.dim))
    }

    // MARK: - マウス

    func testClickOnDisabledViewReachesNeitherItNorViewBelow() async {
        let list = ListState()
        let harness = FocusHarness(size: Size(width: 10, height: 4)) {
            VStack(spacing: 0) {
                TextField(state: self.first)
                ListView(items: ["a", "b", "c"], state: list)
                    .frame(height: 3)
                    .overlay(
                        TextField(state: self.second).frame(width: 3, height: 1).disabled(true),
                        horizontal: .leading,
                        vertical: .bottom
                    )
            }
        }

        XCTAssertFalse(harness.click(at: Point(x: 0, y: 3)))
        harness.press(.character("f"))

        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertEqual(first.text, "f")
        XCTAssertEqual(second.text, "")
        XCTAssertTrue(harness.click(at: Point(x: 0, y: 2)))
        XCTAssertEqual(list.selectedIndex, 1)
    }

    func testWheelOnDisabledListDoesNotScroll() async {
        let list = ListState()
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            ListView(items: ["a", "b", "c", "d"], state: list)
                .disabled(true)
        }

        XCTAssertFalse(harness.click(at: Point(x: 0, y: 0), action: .scrollDown))

        XCTAssertEqual(list.scrollOffset, 0)
        XCTAssertEqual(list.selectedIndex, 0)
    }

    // MARK: - @FocusState

    func testAssignmentToDisabledViewIsAppliedWhenEnabledByNextDraw() async {
        var isNoteLocked = true
        var form: LockableForm?
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            let made = LockableForm(nameState: self.first, noteState: self.second, isNoteLocked: isNoteLocked)
            form = made
            return made
        }
        XCTAssertEqual(form?.field, .name)

        isNoteLocked = false
        form?.field = .note
        XCTAssertEqual(form?.field, .name)
        harness.draw()

        XCTAssertEqual(form?.field, .note)
        harness.press(.character("n"))
        XCTAssertEqual(second.text, "n")
    }

    func testAssignmentToViewStillDisabledIsDropped() async {
        var form: LockableForm?
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            let made = LockableForm(nameState: self.first, noteState: self.second, isNoteLocked: true)
            form = made
            return made
        }

        form?.field = .note
        harness.draw()
        harness.draw()

        XCTAssertEqual(form?.field, .name)
    }

    func testFocusedEqualsSkipsDisabledViewInside() async {
        struct Screen: View {
            enum Field: Hashable {
                case top
                case group
            }

            let top: TextFieldState
            let locked: TextFieldState
            let open: TextFieldState
            @FocusState var field: Field?

            var body: some View {
                VStack(spacing: 0) {
                    TextField(state: top).focused($field, equals: .top)
                    VStack(spacing: 0) {
                        TextField(state: locked).disabled(true)
                        TextField(state: open)
                    }
                    .focused($field, equals: .group)
                }
            }
        }
        var screen: Screen?
        let harness = FocusHarness(size: Size(width: 10, height: 3)) {
            let made = Screen(top: self.first, locked: self.second, open: self.third)
            screen = made
            return made
        }

        screen?.field = .group
        harness.draw()

        XCTAssertEqual(screen?.field, .group)
        harness.press(.character("o"))
        XCTAssertEqual(third.text, "o")
        XCTAssertEqual(second.text, "")
    }

    // MARK: - 見た目

    func testDisabledTextFieldAndListViewAreDimButTextIsNot() async {
        let field = TextFieldState(text: "ab")
        let list = ListState()
        for isDisabled in [false, true] {
            var buffer = Buffer(size: Size(width: 6, height: 4))
            let bounds = buffer.bounds
            VStack(spacing: 0) {
                TextField(state: field)
                ListView(items: ["x", "y"], state: list).frame(height: 2)
                Text("t")
            }
            .disabled(isDisabled)
            .renderAsRoot(into: &buffer, rect: bounds)

            XCTAssertEqual(buffer[0, 0].style.attributes.contains(.dim), isDisabled, "TextField, disabled: \(isDisabled)")
            XCTAssertEqual(buffer[0, 1].style.attributes.contains(.dim), isDisabled, "選択行, disabled: \(isDisabled)")
            XCTAssertTrue(buffer[0, 1].style.attributes.contains(.reverse))
            XCTAssertEqual(buffer[0, 2].style.attributes.contains(.dim), isDisabled, "選択していない行, disabled: \(isDisabled)")
            XCTAssertFalse(buffer[0, 3].style.attributes.contains(.dim), "Text, disabled: \(isDisabled)")
        }
    }

    func testViewsBehindSheetAreNotDim() async {
        let harness = FocusHarness(size: Size(width: 20, height: 5)) {
            TextField(state: self.first)
                .sheet(isPresented: Binding(get: { true }, set: { _ in })) {
                    TextField(state: self.second).frame(width: 8, height: 1)
                }
        }

        XCTAssertFalse(harness.buffer[0, 0].style.attributes.contains(.dim))
    }
}
