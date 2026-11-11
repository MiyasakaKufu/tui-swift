import XCTest
@testable import TUIKit

/// `Row` の `@State` の `Binding` を、`Row.name` ごとに記録するクラス。
@MainActor
private final class RowLog {
    /// 最後に `Row.body` の値を取得したときの `Binding`。
    var bindings: [String: Binding<Int>] = [:]
    /// `View.task(_:)` のクロージャが呼び出された回数。
    var taskStarts = 0
    /// `View.onChange(of:_:)` のクロージャが呼び出された回数。
    var changes = 0

    /// `name` の `Row` の `@State` の値を返す。
    ///
    /// - Parameters:
    ///   - name: `Row.name`。
    /// - Returns: 最後に `Row.body` の値を取得したときの `@State` の値。記録が無ければ `nil`。
    func count(of name: String) -> Int? {
        bindings[name]?.wrappedValue
    }
}

/// 数を `@State` に持ち、`View.body` の値を取得するたびに `$count` を `RowLog` に記録する `View`。
private struct Row: View {
    /// 記録に使う名前。
    let name: String
    /// 記録先。
    let log: RowLog
    @State var count = 0

    var body: some View {
        log.bindings[name] = $count
        return Text("\(name):\(count)")
    }
}

/// 受け取った `RenderContext.node` の `ViewNode.id` を、描画した順に記録する `View`。
private struct NodeRecorder: PrimitiveView {
    /// 記録する名前。
    let name: String
    /// 描画した順に、名前と `ViewNode.id` を追加する配列を持つクラス。
    let log: NodeIDLog

    /// 幅 1・高さ 1 の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:slot:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 幅 1・高さ 1 の `Size`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: 1, height: 1)
    }

    /// `ViewNode.id` を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        log.entries.append((name, context.node.id))
    }

    /// `RenderContext` のメソッドに `View` を渡さないので、何もしない。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる `View` を受け取る `ViewVisitor`。
    func visitChildren(_ visitor: ViewVisitor) {}
}

/// `NodeRecorder` が描画した順に、名前と `ViewNode.id` を記録するクラス。
@MainActor
private final class NodeIDLog {
    /// 描画した順に並べた、名前と `ViewNode.id` の組。
    var entries: [(name: String, id: Int)] = []
}

/// `ViewList` を 2 つ受け取り、どちらの要素も同じ `RenderContext` で縦に描く `View`。
private struct TwoLists: PrimitiveView {
    /// 先に描く `ViewList`。`slot` 引数を 0 として渡す。
    let first: ViewList
    /// 後に描く `ViewList`。`slot` 引数を 1 として渡す。
    let second: ViewList

    /// 2 つの `ViewList` から `TwoLists` を作る。
    ///
    /// - Parameters:
    ///   - first: 先に描く `View` を返すクロージャ。
    ///   - second: 後に描く `View` を返すクロージャ。
    init(@ViewBuilder first: () -> ViewList, @ViewBuilder second: () -> ViewList) {
        self.first = first()
        self.second = second()
    }

    /// `proposal` をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:slot:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `proposal`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        proposal
    }

    /// 2 つの `ViewList` の要素を、1 行に 1 つずつ描く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        var y = rect.minY
        for (slot, list) in [first, second].enumerated() {
            for element in list {
                context.render(element, slot: slot, into: &buffer, rect: Rect(x: rect.minX, y: y, width: rect.width, height: 1))
                y += 1
            }
        }
    }

    /// `TwoLists.first` の要素を `slot` 引数を 0 として、`TwoLists.second` の要素を `slot` 引数を 1 として、`visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる `View` を受け取る `ViewVisitor`。
    func visitChildren(_ visitor: ViewVisitor) {
        for element in first {
            visitor.visit(element, slot: 0)
        }
        for element in second {
            visitor.visit(element, slot: 1)
        }
    }
}

/// 1 つの `ViewList` の要素を、`slot` 引数を変えて 2 回ずつ描く `View`。
private struct Twice: PrimitiveView {
    /// 描く `ViewList`。
    let content: ViewList

    /// `content` が返す `View` を 2 回ずつ描く `Twice` を作る。
    ///
    /// - Parameters:
    ///   - content: 描く `View` を返すクロージャ。
    init(@ViewBuilder content: () -> ViewList) {
        self.content = content()
    }

    /// `proposal` をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:slot:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `proposal`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        proposal
    }

    /// `Twice.content` の要素を、`slot` 引数を 0 と 1 にして 1 回ずつ描く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        for copy in 0..<2 {
            for element in content {
                context.render(element, slot: copy, into: &buffer, rect: rect)
            }
        }
    }

    /// `Twice.content` の要素を、`slot` 引数を 0 と 1 にして 1 回ずつ `visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる `View` を受け取る `ViewVisitor`。
    func visitChildren(_ visitor: ViewVisitor) {
        for copy in 0..<2 {
            for element in content {
                visitor.visit(element, slot: copy)
            }
        }
    }
}

/// `@State` を付けたプロパティの文字列を `TextField` で編集する `View`。
private struct NameField: View {
    /// カーソル位置を持つ `TextFieldState`。
    let state: TextFieldState
    /// `NameField.text` の `Binding` を記録するクラス。
    let log: NameLog
    @State var text = ""

    var body: some View {
        log.binding = $text
        return TextField(text: $text, state: state)
    }
}

/// `NameField` の `Binding` を記録するクラス。
@MainActor
private final class NameLog {
    /// 最後に `NameField.body` の値を取得したときの `Binding`。
    var binding: Binding<String>?
}

@MainActor
final class ViewListTests: XCTestCase {
    private let log = RowLog()

    private func frame(_ view: some View, graph: ViewGraph) {
        var buffer = Buffer(size: Size(width: 10, height: 8))
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth)
    }

    /// `makeView(first)` を描いてから `Row` の `name` の値を 7 にし、`makeView(second)` を描いた後の値を返す。
    ///
    /// - Parameters:
    ///   - name: 値を書き換える `Row` の `Row.name`。
    ///   - first: 1 回目の描画で `makeView` に渡す値。
    ///   - second: 2 回目の描画で `makeView` に渡す値。
    ///   - makeView: 描く `View` を返すクロージャ。
    /// - Returns: 2 回目の描画の後の、`name` の `Row` の `@State` の値。
    private func countAfterSwitching<Input, V: View>(
        _ name: String,
        from first: Input,
        to second: Input,
        _ makeView: (Input) -> V
    ) -> Int? {
        let graph = ViewGraph()
        frame(makeView(first), graph: graph)
        log.bindings[name]?.wrappedValue = 7
        frame(makeView(second), graph: graph)
        return log.count(of: name)
    }

    // MARK: - 前に置いた `if` の中の `View` が現れたり消えたりしたとき

    func testStateAfterIfIsKept() async {
        let log = self.log
        let count = countAfterSwitching("row", from: false, to: true) { (shows: Bool) in
            VStack {
                if shows { Text("hint") }
                Row(name: "row", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterIfIsKeptWhenIfDisappears() async {
        let log = self.log
        let count = countAfterSwitching("row", from: true, to: false) { (shows: Bool) in
            VStack {
                if shows { Text("hint") }
                Row(name: "row", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterIfElseIsKept() async {
        let log = self.log
        let count = countAfterSwitching("row", from: true, to: false) { (isLong: Bool) in
            VStack {
                if isLong {
                    Text("a")
                    Text("b")
                } else {
                    Text("c")
                }
                Row(name: "row", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterForIsKeptWhenCountChanges() async {
        let log = self.log
        let count = countAfterSwitching("row", from: 1, to: 3) { (repeats: Int) in
            VStack {
                for index in 0..<repeats {
                    Text("\(index)")
                }
                Row(name: "row", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateInsideNestedIfIsKeptWhenInnerIfChanges() async {
        let log = self.log
        let count = countAfterSwitching("inner", from: false, to: true) { (showsInner: Bool) in
            VStack {
                if true {
                    if showsInner { Text("x") }
                    Row(name: "inner", log: log)
                }
                Row(name: "after", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterNestedIfIsKeptWhenOuterIfDisappears() async {
        let log = self.log
        let count = countAfterSwitching("after", from: true, to: false) { (showsOuter: Bool) in
            VStack {
                if showsOuter {
                    Text("a")
                    if showsOuter { Text("b") }
                }
                Row(name: "after", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateInsideForIsKeptWhenIfInSameIterationChanges() async {
        let log = self.log
        let count = countAfterSwitching("row1", from: false, to: true) { (showsBadge: Bool) in
            VStack {
                for index in 0..<2 {
                    if showsBadge { Text("new") }
                    Row(name: "row\(index)", log: log)
                }
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterIfInsideForIsKept() async {
        let log = self.log
        let count = countAfterSwitching("after", from: false, to: true) { (showsBadge: Bool) in
            VStack {
                for _ in 0..<2 {
                    if showsBadge { Text("new") }
                }
                Row(name: "after", log: log)
            }
        }
        XCTAssertEqual(count, 7)
    }

    func testStateAfterIfInViewBuilderFunctionIsKept() async {
        let log = self.log
        @ViewBuilder func header(_ shows: Bool) -> ViewList {
            if shows { Text("hint") }
            Row(name: "inHeader", log: log)
        }
        let count = countAfterSwitching("inHeader", from: false, to: true) { (shows: Bool) in
            VStack {
                header(shows)
                Text("body")
            }
        }
        XCTAssertEqual(count, 7)
    }

    // MARK: - `if`-`else` の分岐が切り替わったとき

    func testSwitchingBranchStartsSameTypeFromInitialValue() async {
        let log = self.log
        let count = countAfterSwitching("row", from: true, to: false) { (flag: Bool) in
            VStack {
                if flag {
                    Row(name: "row", log: log)
                } else {
                    Row(name: "row", log: log)
                }
            }
        }
        XCTAssertEqual(count, 0)
    }

    func testSameIDInBothBranchesKeepsState() async {
        let log = self.log
        let count = countAfterSwitching("row", from: true, to: false) { (flag: Bool) in
            VStack {
                if flag {
                    Row(name: "row", log: log).id("row")
                } else {
                    Row(name: "row", log: log).id("row")
                }
            }
        }
        XCTAssertEqual(count, 7)
    }

    // MARK: - 配列から作った `ViewList`

    func testViewsFromArrayAreIdentifiedByPosition() async {
        let log = self.log
        let count = countAfterSwitching("row", from: false, to: true) { (prepends: Bool) in
            VStack(children: (prepends ? [Text("x")] : []) + [Row(name: "row", log: log)])
        }
        XCTAssertEqual(count, 0)
    }

    // MARK: - `slot` 引数

    func testSlotSeparatesElementsAtSamePositionInTwoLists() async {
        let nodes = NodeIDLog()
        frame(
            TwoLists(
                first: { NodeRecorder(name: "first", log: nodes) },
                second: { NodeRecorder(name: "second", log: nodes) }
            ),
            graph: ViewGraph()
        )

        XCTAssertEqual(nodes.entries.map(\.name), ["first", "second"])
        XCTAssertNotEqual(nodes.entries[0].id, nodes.entries[1].id)
    }

    func testSlotSeparatesSameElementDrawnTwice() async {
        let nodes = NodeIDLog()
        frame(Twice { NodeRecorder(name: "copy", log: nodes) }, graph: ViewGraph())

        XCTAssertEqual(nodes.entries.count, 2)
        XCTAssertNotEqual(nodes.entries[0].id, nodes.entries[1].id)
    }

    // MARK: - `View.task(_:)` と `View.onChange(of:_:)`

    func testTaskAfterIfIsNotRestarted() async {
        let log = self.log
        var shows = false
        let harness = FocusHarness(size: Size(width: 10, height: 4)) {
            VStack {
                if shows { Text("hint") }
                Text("x").task { log.taskStarts += 1 }
            }
        }
        await waitForTasks()

        shows = true
        harness.draw()
        await waitForTasks()

        XCTAssertEqual(log.taskStarts, 1)
    }

    func testOnChangeAfterIfReportsChangeMadeTogether() async {
        let log = self.log
        var shows = false
        var value = 0
        let harness = FocusHarness(size: Size(width: 10, height: 4)) {
            VStack {
                if shows { Text("hint") }
                Text("x").onChange(of: value) { _, _ in log.changes += 1 }
            }
        }

        shows = true
        value = 1
        harness.draw()

        XCTAssertEqual(log.changes, 1)
    }

    /// `View.task(_:)` で始めた `Task` が動けるよう、メインアクターを何度か譲る。
    private func waitForTasks() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    // MARK: - issue #143 の再現手順

    func testTextAndFocusAfterIfAreKept() async {
        let firstState = TextFieldState()
        let nameState = TextFieldState()
        let nameLog = NameLog()
        var showsHint = false
        let harness = FocusHarness(size: Size(width: 10, height: 4)) {
            VStack {
                if showsHint { Text("hint") }
                TextField(state: firstState)
                NameField(state: nameState, log: nameLog)
            }
        }
        harness.press(.tab)
        harness.press(.character("7"))
        XCTAssertEqual(nameLog.binding?.wrappedValue, "7")

        showsHint = true
        harness.draw()
        harness.press(.character("8"))

        XCTAssertEqual(nameLog.binding?.wrappedValue, "78")
        XCTAssertEqual(firstState.text, "")
    }
}
