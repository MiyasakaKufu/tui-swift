import XCTest
@testable import TUIKit

/// `TextField` 2 つと `ListView` を縦に並べた `View`。
private struct Form: View {
    enum Field: Hashable {
        case name
        case note
        case list
    }

    let nameState: TextFieldState
    let noteState: TextFieldState
    let listState: ListState
    var showsNote = true
    var onEnterInForm: (() -> EventResult)?
    @FocusState var focusedField: Field?
    @State var selection = 0

    var body: some View {
        VStack(spacing: 0) {
            TextField(state: nameState)
                .focused($focusedField, equals: .name)
            if showsNote {
                TextField(state: noteState)
                    .focused($focusedField, equals: .note)
            }
            // `View.id(_:)` を外したくなるが、外すと `showsNote` を切り替えたときに `ListView` の `ViewPath.Component` がずれ（#143）、フォーカスを失う。
            ListView(items: ["a", "b", "c"], selection: $selection, state: listState)
                .frame(height: 3)
                .focused($focusedField, equals: .list)
                .id(Field.list)
        }
        .onKeyPress(.enter) { onEnterInForm?() ?? .ignored }
    }
}

@MainActor
final class FocusTests: XCTestCase {
    private lazy var nameState = TextFieldState()
    private lazy var noteState = TextFieldState()
    private lazy var listState = ListState()

    private func makeForm(showsNote: Bool = true) -> Form {
        Form(nameState: nameState, noteState: noteState, listState: listState, showsNote: showsNote)
    }

    // MARK: - 最初のフォーカスと Tab の順

    func testFirstDrawFocusesFirstTargetInVisitOrder() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }

        harness.press(.character("x"))

        XCTAssertEqual(nameState.text, "x")
        XCTAssertEqual(noteState.text, "")
    }

    func testOnlyFocusedTextFieldShowsReversedCursor() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }

        XCTAssertTrue(harness.buffer[0, 0].style.attributes.contains(.reverse))
        XCTAssertFalse(harness.buffer[0, 1].style.attributes.contains(.reverse))

        harness.press(.tab)

        XCTAssertFalse(harness.buffer[0, 0].style.attributes.contains(.reverse))
        XCTAssertTrue(harness.buffer[0, 1].style.attributes.contains(.reverse))
    }

    func testTabAndShiftTabCycleInVisitOrder() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }

        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.character("n"))
        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.down)
        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.character("m"))
        XCTAssertEqual(harness.press(.backTab), .handled)
        harness.press(.up)

        XCTAssertEqual(nameState.text, "m")
        XCTAssertEqual(noteState.text, "n")
        XCTAssertEqual(listState.selectedIndex, 0)
    }

    func testTabIsNotHandledWithoutFocusTargets() async {
        let harness = FocusHarness(size: Size(width: 10, height: 2)) { Text("only") }

        XCTAssertNil(harness.press(.tab))
    }

    func testTargetNotDrawnInShortVStackStillReceivesFocusWithoutCursor() async {
        let first = TextFieldState()
        let hidden = TextFieldState()
        let harness = FocusHarness(size: Size(width: 10, height: 1)) {
            VStack(spacing: 0) {
                TextField(state: first)
                TextField(state: hidden)
            }
        }
        XCTAssertNotNil(harness.context.cursorPosition)

        harness.press(.tab)
        harness.press(.character("z"))

        XCTAssertEqual(hidden.text, "z")
        XCTAssertNil(harness.context.cursorPosition)
    }

    // MARK: - キーの渡し方

    func testUnhandledKeyGoesToEnclosingOnKeyPressThenReturnsNil() async {
        var enterCount = 0
        let harness = FocusHarness(size: Size(width: 10, height: 5)) {
            var form = self.makeForm()
            form.onEnterInForm = {
                enterCount += 1
                return .handled
            }
            return form
        }

        XCTAssertEqual(harness.press(.enter), .handled)
        XCTAssertEqual(enterCount, 1)
        XCTAssertNil(harness.press(.escape))
    }

    func testInnerOnKeyPressRunsBeforeOuter() async {
        var calls: [String] = []
        let state = TextFieldState()
        let harness = FocusHarness(size: Size(width: 10, height: 1)) {
            TextField(state: state)
                .onKeyPress(.enter) {
                    calls.append("inner")
                    return .ignored
                }
                .onKeyPress(.enter) {
                    calls.append("outer")
                    return .handled
                }
        }

        XCTAssertEqual(harness.press(.enter), .handled)
        XCTAssertEqual(calls, ["inner", "outer"])
    }

    func testOnKeyPressIgnoresModifiersExceptShiftOnCharacters() async {
        var count = 0
        let list = ListState()
        let harness = FocusHarness(size: Size(width: 10, height: 3)) {
            ListView(items: ["a"], state: list)
                .onKeyPress(.character("s")) {
                    count += 1
                    return .handled
                }
        }

        XCTAssertNil(harness.press(.character("s"), modifiers: .control))
        XCTAssertEqual(harness.press(.character("s"), modifiers: .shift), .handled)
        XCTAssertEqual(count, 1)
    }

    func testPasteGoesToFocusedTextField() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }
        harness.press(.tab)

        XCTAssertTrue(harness.paste("貼"))

        XCTAssertEqual(noteState.text, "貼")
    }

    // MARK: - マウス

    func testClickMovesFocusAndDeliversToClickedView() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }

        XCTAssertTrue(harness.click(at: Point(x: 0, y: 3)))
        harness.press(.down)

        XCTAssertEqual(listState.selectedIndex, 2)
    }

    func testClickOnTextOverListDoesNotReachList() async {
        let list = ListState()
        let harness = FocusHarness(size: Size(width: 10, height: 3)) {
            ListView(items: ["a", "b", "c"], state: list)
                .overlay(Text("x"), horizontal: .leading, vertical: .bottom)
        }

        XCTAssertFalse(harness.click(at: Point(x: 0, y: 2)))
        XCTAssertEqual(list.selectedIndex, 0)
        XCTAssertTrue(harness.click(at: Point(x: 0, y: 1)))
        XCTAssertEqual(list.selectedIndex, 1)
    }

    func testWheelDoesNotMoveFocus() async {
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm() }

        harness.click(at: Point(x: 0, y: 3), action: .scrollDown)
        harness.press(.character("w"))

        XCTAssertEqual(nameState.text, "w")
    }

    // MARK: - フォーカスを決める時機

    func testFocusedViewNoLongerVisitedMovesFocusToFirst() async {
        var showsNote = true
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { self.makeForm(showsNote: showsNote) }
        harness.press(.tab)

        showsNote = false
        harness.draw()
        harness.press(.character("q"))

        XCTAssertEqual(nameState.text, "q")
    }

    func testTargetAppearingLaterReceivesFocus() async {
        var showsField = false
        let state = TextFieldState()
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            VStack(spacing: 0) {
                Text("top")
                if showsField {
                    TextField(state: state)
                }
            }
        }

        showsField = true
        harness.draw()
        harness.press(.character("a"))

        XCTAssertEqual(state.text, "a")
    }

    // MARK: - @FocusState

    func testFocusStateReflectsFocusAndAssignmentMovesFocus() async {
        let form = makeForm()
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { form }
        XCTAssertEqual(form.focusedField, .name)

        form.focusedField = .list
        XCTAssertEqual(form.focusedField, .list)
        harness.draw()
        harness.press(.down)

        XCTAssertEqual(listState.selectedIndex, 1)
    }

    func testAssigningNilRemovesFocusUntilTab() async {
        let form = makeForm()
        let harness = FocusHarness(size: Size(width: 10, height: 5)) { form }

        form.focusedField = nil
        harness.draw()

        XCTAssertNil(form.focusedField)
        XCTAssertNil(harness.press(.character("x")))
        XCTAssertEqual(nameState.text, "")

        harness.press(.tab)
        XCTAssertEqual(form.focusedField, .name)
    }

    func testAssignmentToViewNotYetVisitedIsAppliedInNextDraw() async {
        var showsNote = false
        var form = makeForm(showsNote: false)
        let harness = FocusHarness(size: Size(width: 10, height: 5)) {
            form = self.makeForm(showsNote: showsNote)
            return form
        }

        form.focusedField = .note
        XCTAssertEqual(form.focusedField, .name)
        showsNote = true
        harness.draw()

        XCTAssertEqual(form.focusedField, .note)
    }

    func testPendingAssignmentIsDroppedByTab() async {
        var showsNote = false
        var form = makeForm(showsNote: false)
        let harness = FocusHarness(size: Size(width: 10, height: 5)) {
            form = self.makeForm(showsNote: showsNote)
            return form
        }

        form.focusedField = .note
        _ = harness.context.deliver(KeyEvent(.tab))
        showsNote = true
        harness.draw()

        XCTAssertEqual(form.focusedField, .list)
    }

    func testBoolFocusStateIsTrueWhileAnyDescendantHasFocus() async {
        struct Group: View {
            let first: TextFieldState
            let second: TextFieldState
            let other: TextFieldState
            @FocusState var isGroupFocused: Bool

            var body: some View {
                VStack(spacing: 0) {
                    VStack(spacing: 0) {
                        TextField(state: first)
                        TextField(state: second)
                    }
                    .focused($isGroupFocused)
                    TextField(state: other)
                }
            }
        }
        let group = Group(first: TextFieldState(), second: TextFieldState(), other: TextFieldState())
        let harness = FocusHarness(size: Size(width: 10, height: 3)) { group }

        XCTAssertTrue(group.isGroupFocused)
        harness.press(.tab)
        XCTAssertTrue(group.isGroupFocused)
        harness.press(.tab)
        XCTAssertFalse(group.isGroupFocused)
    }

    // MARK: - 続けて行う Application.draw()

    func testFocusDecidedAfterVisitingRedrawsOnceSoListMatchesFocus() async {
        struct Expanding: View {
            let first: TextFieldState
            let extra: TextFieldState
            @FocusState var isFocused: Bool

            var body: some View {
                VStack(spacing: 0) {
                    TextField(state: first)
                    if isFocused {
                        TextField(state: extra)
                    }
                }
                .focused($isFocused)
            }
        }
        let extra = TextFieldState()
        let harness = FocusHarness(size: Size(width: 10, height: 2)) {
            Expanding(first: TextFieldState(), extra: extra)
        }

        XCTAssertEqual(harness.presentCount, 2)
        harness.press(.tab)
        harness.press(.character("e"))

        XCTAssertEqual(extra.text, "e")
    }

    func testOscillatingBodyStopsAfterOneFollowUp() async {
        struct Oscillating: View {
            enum Field: Hashable {
                case a
                case b
            }

            let a: TextFieldState
            let b: TextFieldState
            @FocusState var field: Field?

            var body: some View {
                VStack(spacing: 0) {
                    if field == .a {
                        TextField(state: b).focused($field, equals: .b)
                    } else {
                        TextField(state: a).focused($field, equals: .a)
                    }
                }
            }
        }
        let harness = FocusHarness(size: Size(width: 10, height: 1)) {
            Oscillating(a: TextFieldState(), b: TextFieldState())
        }

        XCTAssertEqual(harness.presentCount, 2)
    }

    func testOnChangeCallsActionAfterDrawAndRedrawsOnce() async {
        var values: [(Int, Int)] = []
        var value = 0
        let harness = FocusHarness(size: Size(width: 10, height: 1)) {
            Text("\(value)").onChange(of: value) { old, new in values.append((old, new)) }
        }
        XCTAssertTrue(values.isEmpty)
        let countBefore = harness.presentCount

        value = 3
        harness.draw()

        XCTAssertEqual(values.map(\.0), [0])
        XCTAssertEqual(values.map(\.1), [3])
        XCTAssertEqual(harness.presentCount - countBefore, 2)
    }

    func testOnChangeThatChangesItsOwnValueStops() async {
        final class Counter {
            var value = 0
        }
        let counter = Counter()
        var calls = 0
        let harness = FocusHarness(size: Size(width: 10, height: 1)) {
            Text("\(counter.value)").onChange(of: counter.value) {
                calls += 1
                counter.value += 1
            }
        }

        counter.value = 1
        let countBefore = harness.presentCount
        harness.draw()

        XCTAssertEqual(harness.presentCount - countBefore, 2)
        XCTAssertEqual(calls, 2)
    }

    // MARK: - View.sheet(isPresented:content:)

    func testSheetMovesFocusInsideAndBlocksViewsBehind() async {
        var isPresented = false
        let back = TextFieldState()
        let front = TextFieldState()
        let harness = FocusHarness(size: Size(width: 20, height: 5)) {
            TextField(state: back)
                .sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                    TextField(state: front).frame(width: 8, height: 1)
                }
        }

        isPresented = true
        harness.draw()
        harness.press(.character("f"))
        XCTAssertEqual(harness.press(.tab), .handled)
        harness.press(.character("g"))
        XCTAssertFalse(harness.click(at: Point(x: 0, y: 0)))
        XCTAssertTrue(harness.paste("p"))

        XCTAssertEqual(front.text, "fgp")
        XCTAssertEqual(back.text, "")

        isPresented = false
        harness.draw()
        harness.press(.character("b"))

        XCTAssertEqual(back.text, "b")
    }

    func testClosingSheetThenAssigningBackViewKeepsAssignment() async {
        struct Screen: View {
            enum Field: Hashable {
                case first
                case second
                case dialog
            }

            let first: TextFieldState
            let second: TextFieldState
            let dialog: TextFieldState
            let isPresented: Binding<Bool>
            @FocusState var field: Field?

            var body: some View {
                VStack(spacing: 0) {
                    TextField(state: first).focused($field, equals: .first)
                    TextField(state: second).focused($field, equals: .second)
                }
                .sheet(isPresented: isPresented) {
                    TextField(state: dialog).focused($field, equals: .dialog).frame(width: 8, height: 1)
                }
            }
        }
        for closesFirst in [true, false] {
            var isPresented = true
            let second = TextFieldState()
            var screen: Screen?
            let harness = FocusHarness(size: Size(width: 20, height: 5)) {
                let made = Screen(
                    first: TextFieldState(),
                    second: second,
                    dialog: TextFieldState(),
                    isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })
                )
                screen = made
                return made
            }
            XCTAssertEqual(screen?.field, .dialog)

            if closesFirst {
                isPresented = false
                screen?.field = .second
            } else {
                screen?.field = .second
                isPresented = false
            }
            harness.draw()
            harness.press(.character("s"))

            XCTAssertEqual(second.text, "s", "closesFirst: \(closesFirst)")
        }
    }

    func testClosingSheetShownFromStartGivesFocusToFirstViewBehind() async {
        var isPresented = true
        let back = TextFieldState()
        let harness = FocusHarness(size: Size(width: 20, height: 5)) {
            TextField(state: back)
                .sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                    TextField(state: TextFieldState()).frame(width: 8, height: 1)
                }
        }

        isPresented = false
        harness.draw()
        harness.press(.character("b"))

        XCTAssertEqual(back.text, "b")
    }
}
