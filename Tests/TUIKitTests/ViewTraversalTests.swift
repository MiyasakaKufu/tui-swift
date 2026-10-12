import XCTest
@testable import TUIKit

/// `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の `beforeRender` が呼び出されたことと、`CallProbe` のメソッドが呼び出されたことを、起きた順に記録するクラス。
@MainActor
private final class TraversalLog {
    /// 起きた順に並べた記録。
    var events: [String] = []
    /// `CallProbe.name` ごとに、最後に `CallProbe.render(into:rect:context:)` が受け取った `RenderContext.node` の `ViewNode.id`。
    var renderedNodeIDs: [String: Int] = [:]
    /// `FieldToggle.body` の値を最後に取得したときの、`FieldToggle.showsField` の `Binding`。
    var showsField: Binding<Bool>?
}

/// `View.sizeThatFits(_:context:)`・`View.layoutTraits(context:)`・`View.render(into:rect:context:)` が呼び出されたことを `TraversalLog` に記録する `View`。
private struct CallProbe: PrimitiveView {
    /// 記録に使う名前。
    let name: String
    /// 記録先。
    let log: TraversalLog

    /// 呼び出されたことを記録し、`LayoutTraits.fixed` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.fixed`。
    func layoutTraits(context: RenderContext) -> LayoutTraits {
        log.events.append("traits \(name)")
        return .fixed
    }

    /// 呼び出されたことを記録し、幅 1・高さ 1 の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 幅 1・高さ 1 の `Size`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        log.events.append("measure \(name)")
        return Size(width: 1, height: 1)
    }

    /// 呼び出されたことと、`RenderContext.node` の `ViewNode.id` を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        log.events.append("render \(name)")
        log.renderedNodeIDs[name] = context.node.id
    }

    /// `RenderContext` のメソッドに `View` を渡さないので、何もしない。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる `View` を受け取る `ViewVisitor`。
    func visitChildren(_ visitor: ViewVisitor) {}
}

/// `State` の値が初期値と違うときだけ、`View.body` に `TextField` を含める `View`。
private struct FieldToggle: View {
    let log: TraversalLog
    let fieldState: TextFieldState
    @State var showsField = false

    var body: some View {
        log.showsField = $showsField
        return VStack {
            Text("label")
            if showsField {
                TextField(state: fieldState)
            }
        }
    }
}

/// `FirstOnly.first` だけを `RenderContext` のメソッドに渡し、`FirstOnly.first` と `FirstOnly.second` の両方を `ViewVisitor` に渡す `View`。
private struct FirstOnly<First: View, Second: View>: PrimitiveView {
    /// `RenderContext` のメソッドに渡す `View`。
    let first: First
    /// `ViewVisitor` にだけ渡す `View`。
    let second: Second

    /// `first` の `View.sizeThatFits(_:context:)` の戻り値を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `first` の `View.sizeThatFits(_:context:)` の戻り値。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: first, index: 0, proposal: proposal)
    }

    /// `first` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(first, index: 0, into: &buffer, rect: rect)
    }

    /// `first` を `index:` 引数を 0 として、`second` を `index:` 引数を 1 として、`visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる `View` を受け取る `ViewVisitor`。
    func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(first, index: 0)
        visitor.visit(second, index: 1)
    }
}

@MainActor
final class ViewTraversalTests: XCTestCase {

    /// `view` を `graph` で 1 回描き、`beforeRender` に渡された `ViewGraph.VisitedView` を返す。
    ///
    /// - Parameters:
    ///   - view: `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の `view` 引数に渡す `View`。
    ///   - graph: 描く `ViewGraph`。
    ///   - log: `beforeRender` が呼び出されたことを記録する `TraversalLog`。
    ///   - width: 描画先の `Buffer` の幅。
    ///   - height: 描画先の `Buffer` の高さ。
    /// - Returns: `beforeRender` に渡された `ViewGraph.VisitedView`。
    private func frame(
        _ view: some View,
        graph: ViewGraph,
        log: TraversalLog,
        width: Int = 10,
        height: Int = 4
    ) -> [ViewGraph.VisitedView] {
        var buffer = Buffer(size: Size(width: width, height: height))
        var visited: [ViewGraph.VisitedView] = []
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth) {
            log.events.append("visited")
            visited = $0
        }
        return visited
    }

    func testVisitedViewsIncludeViewsFromStateDependentBodyBeforeFirstRender() async {
        let graph = ViewGraph()
        let log = TraversalLog()
        let fieldState = TextFieldState()
        let listState = ListState()
        func view() -> some View {
            VStack {
                CallProbe(name: "probe", log: log)
                FieldToggle(log: log, fieldState: fieldState)
                ListView(items: ["a"], state: listState)
            }
        }

        let first = frame(view(), graph: graph, log: log)
        XCTAssertEqual(first.filter { $0.view is TextField }.count, 0)
        XCTAssertEqual(first.filter { $0.view is ListView }.count, 1)

        log.showsField?.wrappedValue = true
        log.events = []
        let second = frame(view(), graph: graph, log: log)

        let widgets = second.compactMap { visited -> String? in
            switch visited.view {
            case is TextField: return "TextField"
            case is ListView: return "ListView"
            default: return nil
            }
        }
        XCTAssertEqual(widgets, ["TextField", "ListView"])
        XCTAssertEqual(log.events.first, "visited")
        XCTAssertTrue(log.events.contains("render probe"))
    }

    func testIdentifiedViewUsesSameNodeInTraversalAndRender() async {
        let graph = ViewGraph()
        let log = TraversalLog()
        var nodeCountBeforeRender = 0
        var visited: [ViewGraph.VisitedView] = []

        var buffer = Buffer(size: Size(width: 10, height: 4))
        let view = VStack {
            Text("x")
            CallProbe(name: "keyed", log: log).id("key")
        }
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth) {
            nodeCountBeforeRender = graph.nodeCount
            visited = $0
        }

        let identified = visited.first { $0.view is IdentifiedView<CallProbe, String> }
        XCTAssertEqual(identified?.node.path, ViewPath.root.appending(.key("key")))
        XCTAssertEqual(visited.first { $0.view is CallProbe }?.node.id, log.renderedNodeIDs["keyed"])
        XCTAssertEqual(graph.nodeCount, nodeCountBeforeRender)
    }

    func testViewsPassedToVisitorAreVisited() async {
        let graph = ViewGraph()
        let log = TraversalLog()
        let view = FirstOnly(
            first: CallProbe(name: "first", log: log),
            second: CallProbe(name: "second", log: log)
        )

        let visited = frame(view, graph: graph, log: log)

        XCTAssertEqual(visited.map(\.node.path), [
            .root,
            ViewPath.root.appending(.index(0)),
            ViewPath.root.appending(.index(1)),
        ])
        XCTAssertEqual(visited[1].node.id, log.renderedNodeIDs["first"])
        XCTAssertNil(log.renderedNodeIDs["second"])
        XCTAssertEqual(graph.nodeCount, 3)
    }

    func testNodeOfViewNotPassedInLayoutOrRenderIsKept() async {
        let graph = ViewGraph()
        let log = TraversalLog()
        let view = CallProbe(name: "inner", log: log).padding(2)

        _ = frame(view, graph: graph, log: log, width: 6, height: 6)
        let before = log.renderedNodeIDs["inner"]
        XCTAssertNotNil(before)

        log.events = []
        _ = frame(view, graph: graph, log: log, width: 3, height: 3)
        XCTAssertEqual(log.events, ["visited"])
        XCTAssertEqual(graph.nodeCount, 2)

        _ = frame(view, graph: graph, log: log, width: 6, height: 6)
        XCTAssertEqual(log.renderedNodeIDs["inner"], before)
    }
}
