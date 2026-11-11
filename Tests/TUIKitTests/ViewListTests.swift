import XCTest
@testable import TUIKit

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

@MainActor
final class ViewListTests: XCTestCase {
    private func frame(_ view: some View, graph: ViewGraph) {
        var buffer = Buffer(size: Size(width: 10, height: 8))
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth)
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
}
