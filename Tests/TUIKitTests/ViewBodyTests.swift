import XCTest
@testable import TUIKit

/// `body` だけを書いた合成ビュー。
private struct Badge: View {
    let label: String

    var body: some View {
        Text(label).padding(horizontal: 1).border()
    }
}

/// 合成ビューを入れ子にした合成ビュー。
private struct BadgeRow: View {
    var body: some View {
        HStack(spacing: 1) {
            Badge(label: "a")
            Badge(label: "b")
        }
    }
}

/// 伸びるビューを `body` に持つ合成ビュー。
private struct Stretch: View {
    var body: some View {
        Fill("*")
    }
}

/// 渡された文脈のノードを、名前ごとに記録する。
@MainActor
private final class NodeLog {
    /// 最後に描かれたときのノードの同一性。
    var rendered: [String: Int] = [:]
    /// 描かれた順に並べたノードの同一性。
    var history: [String: [Int]] = [:]
}

/// 渡された文脈のノードを記録するビュー。
private struct NodeProbe: PrimitiveView {
    /// 記録に使う名前。
    let name: String
    /// 記録先。
    let log: NodeLog

    /// 1 桁・1 行を希望する。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 1 桁・1 行のサイズ。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: 1, height: 1)
    }

    /// ノードの同一性を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        log.rendered[name] = context.node.id
        log.history[name, default: []].append(context.node.id)
    }
}

/// `NodeProbe` を包む合成ビュー。
private struct WrappedProbe: View {
    let name: String
    let log: NodeLog

    var body: some View {
        NodeProbe(name: name, log: log)
    }
}

@MainActor
final class ViewBodyTests: XCTestCase {

    private func frame(_ view: some View, graph: ViewGraph, width: Int = 10, height: Int = 4) -> Buffer {
        var buffer = Buffer(size: Size(width: width, height: height))
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth)
        return buffer
    }

    // MARK: - body

    func testCompositeViewDrawsItsBody() async {
        var composite = Buffer(size: Size(width: 12, height: 3))
        BadgeRow().renderAsRoot(into: &composite, rect: composite.bounds)

        var expanded = Buffer(size: Size(width: 12, height: 3))
        HStack(spacing: 1) {
            Text("a").padding(horizontal: 1).border()
            Text("b").padding(horizontal: 1).border()
        }
        .renderAsRoot(into: &expanded, rect: expanded.bounds)

        XCTAssertEqual(composite.debugText(), expanded.debugText())
        XCTAssertEqual(composite.text(ofRow: 1), "│ a │ │ b │ ")
    }

    func testCompositeViewMeasuresAsItsBody() async {
        XCTAssertEqual(Badge(label: "abc").sizeThatFitsAsRoot(Size(width: 20, height: 5)), Size(width: 7, height: 3))
    }

    func testCompositeViewTakesLayoutTraitsFromItsBody() async {
        XCTAssertEqual(Stretch().layoutTraitsAsRoot(), .flexible)
        XCTAssertEqual(Badge(label: "a").layoutTraitsAsRoot(), .fixed)

        var buffer = Buffer(size: Size(width: 3, height: 2))
        VStack {
            Text("x")
            Stretch()
        }
        .renderAsRoot(into: &buffer, rect: buffer.bounds)
        XCTAssertEqual(buffer.debugText(), "x  \n***")
    }

    func testCompositeAndPrimitiveViewsMixInOneStack() async {
        let children: [any View] = [Text("t"), Badge(label: "b")]
        var buffer = Buffer(size: Size(width: 6, height: 4))
        VStack(children: children).renderAsRoot(into: &buffer, rect: buffer.bounds)
        XCTAssertEqual(buffer.text(ofRow: 0), "t     ")
        XCTAssertEqual(buffer.text(ofRow: 2), "│ b │ ")
    }

    // MARK: - 同一性

    func testSamePositionKeepsIdentityAcrossFrames() async {
        let graph = ViewGraph()
        let log = NodeLog()
        func view() -> some View {
            VStack {
                NodeProbe(name: "a", log: log)
                WrappedProbe(name: "b", log: log)
            }
        }

        _ = frame(view(), graph: graph)
        let first = log.rendered
        _ = frame(view(), graph: graph, width: 5, height: 2)

        XCTAssertEqual(log.rendered, first)
        XCTAssertNotEqual(first["a"], first["b"])
    }

    func testSameViewValueInTwoPlacesGetsTwoIdentities() async {
        let graph = ViewGraph()
        let log = NodeLog()
        let shared = NodeProbe(name: "shared", log: log)

        _ = frame(HStack { shared; shared }, graph: graph)

        let identities = log.history["shared"] ?? []
        XCTAssertEqual(identities.count, 2)
        XCTAssertEqual(Set(identities).count, 2)
    }

    func testChangingTypeAtSamePositionCreatesNewIdentityForSubtree() async {
        let graph = ViewGraph()
        let log = NodeLog()

        _ = frame(VStack { NodeProbe(name: "p", log: log) }, graph: graph)
        let before = log.rendered["p"]
        _ = frame(HStack { NodeProbe(name: "p", log: log) }, graph: graph)

        XCTAssertNotEqual(log.rendered["p"], before)
    }

    func testConditionalViewShiftsIdentityOfLaterSiblings() async {
        let graph = ViewGraph()
        let log = NodeLog()
        func view(showsBanner: Bool) -> some View {
            VStack {
                if showsBanner {
                    Text("!")
                }
                NodeProbe(name: "plain", log: log)
                NodeProbe(name: "keyed", log: log).id("keyed")
            }
        }

        _ = frame(view(showsBanner: false), graph: graph)
        let before = log.rendered
        _ = frame(view(showsBanner: true), graph: graph)

        XCTAssertNotEqual(log.rendered["plain"], before["plain"])
        XCTAssertEqual(log.rendered["keyed"], before["keyed"])
    }

    func testKeyKeepsIdentityWhenReordered() async {
        let graph = ViewGraph()
        let log = NodeLog()
        func view(_ names: [String]) -> some View {
            VStack {
                for name in names {
                    NodeProbe(name: name, log: log).id(name)
                }
            }
        }

        _ = frame(view(["x", "y"]), graph: graph)
        let before = log.rendered
        _ = frame(view(["y", "x"]), graph: graph)

        XCTAssertEqual(log.rendered, before)
    }

    func testChangingKeyCreatesNewIdentity() async {
        let graph = ViewGraph()
        let log = NodeLog()

        _ = frame(VStack { NodeProbe(name: "p", log: log).id(1) }, graph: graph)
        let before = log.rendered["p"]
        _ = frame(VStack { NodeProbe(name: "p", log: log).id(2) }, graph: graph)

        XCTAssertNotEqual(log.rendered["p"], before)
    }

    // MARK: - ノードの破棄

    func testNodesNotVisitedInFrameAreDiscarded() async {
        let graph = ViewGraph()
        let log = NodeLog()
        func view(count: Int) -> some View {
            VStack {
                for index in 0..<count {
                    NodeProbe(name: "\(index)", log: log)
                }
            }
        }

        _ = frame(view(count: 3), graph: graph)
        XCTAssertEqual(graph.nodeCount, 4)
        let first = log.rendered["0"]

        _ = frame(view(count: 1), graph: graph)
        XCTAssertEqual(graph.nodeCount, 2)
        XCTAssertEqual(log.rendered["0"], first)
    }

    func testDiscardedPositionGetsNewIdentityWhenItReturns() async {
        let graph = ViewGraph()
        let log = NodeLog()
        func view(showsProbe: Bool) -> some View {
            VStack {
                if showsProbe {
                    NodeProbe(name: "p", log: log)
                }
            }
        }

        _ = frame(view(showsProbe: true), graph: graph)
        let before = log.rendered["p"]
        _ = frame(view(showsProbe: false), graph: graph)
        _ = frame(view(showsProbe: true), graph: graph)

        XCTAssertNotEqual(log.rendered["p"], before)
    }
}
