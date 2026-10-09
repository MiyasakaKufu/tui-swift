import XCTest
@testable import TUIKit

/// `BindingProbe.sizeThatFits(_:context:)` と `PrimitiveCounter.render(into:rect:context:)` が渡す `Binding` を、名前ごとに、渡された順に記録するクラス。
@MainActor
private final class BindingLog {
    /// 名前ごとに、記録された順に並べた `Binding`。
    var bindings: [String: [Binding<Int>]] = [:]

    /// `name` で最後に記録された `Binding` を返す。
    ///
    /// - Parameters:
    ///   - name: 記録に使った名前。
    /// - Returns: 最後に記録された `Binding`。記録されていなければ `nil`。
    func last(_ name: String) -> Binding<Int>? {
        bindings[name]?.last
    }
}

/// `BindingProbe.sizeThatFits(_:context:)` が呼び出されたときに、渡された `binding` を記録する `View`。
private struct BindingProbe: PrimitiveView {
    /// 記録に使う名前。
    let name: String
    /// 記録する `Binding`。
    let binding: Binding<Int>
    /// 記録先。
    let log: BindingLog

    /// `binding` を記録し、大きさを持たないことを返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.zero`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        log.bindings[name, default: []].append(binding)
        return .zero
    }

    /// 何も描画しない。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {}
}

/// 数を `State` に持ち、`View.body` で表示する `View`。
private struct Counter: View {
    let name: String
    let log: BindingLog
    @State var count = 0

    var body: some View {
        HStack {
            Text("\(count)")
            BindingProbe(name: name, binding: $count, log: log)
        }
    }
}

/// `State` を持つ `PrimitiveView`。
private struct PrimitiveCounter: PrimitiveView {
    let log: BindingLog
    @State var count = 0

    /// 数の表示に要る大きさを返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 幅が数の桁数、高さが 1 の `Size`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: "\(count)".count, height: 1)
    }

    /// 数を描き、`$count` を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        buffer.write("\(count)", at: rect.origin, clippedTo: rect)
        log.bindings["primitive", default: []].append($count)
    }
}

/// `State` の値で、`LayoutTraits.flex(on:)` が 1 以上かどうかが変わる、`View.body` を持つ `View`。
private struct Expander: View {
    let log: BindingLog
    @State var level = 0

    var body: some View {
        HStack {
            BindingProbe(name: "expander", binding: $level, log: log)
            if level > 0 {
                Fill("*")
            } else {
                Text("-")
            }
        }
    }
}

/// `nil` を取りうる値を `State` に持ち、`View.body` で `Text` を返す `View`。
private struct OptionalHolder: View {
    let log: OptionalLog
    @State var text: String? = "initial"

    var body: some View {
        log.binding = $text
        return Text(text ?? "nil")
    }
}

/// `OptionalHolder` の `Binding` を記録するクラス。
@MainActor
private final class OptionalLog {
    /// 最後に評価された `View.body` の `Binding`。
    var binding: Binding<String?>?
}

@MainActor
final class StateTests: XCTestCase {

    private func frame(_ view: some View, graph: ViewGraph, width: Int = 8, height: Int = 3) -> Buffer {
        var buffer = Buffer(size: Size(width: width, height: height))
        graph.renderFrame(view, into: &buffer, ambiguousWidth: buffer.ambiguousWidth)
        return buffer
    }

    // MARK: - 値の保持

    func testStateKeepsValueAcrossFrames() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view() -> some View {
            VStack { Counter(name: "c", log: log) }
        }

        XCTAssertEqual(frame(view(), graph: graph).text(ofRow: 0), "0       ")
        log.last("c")?.wrappedValue = 42
        XCTAssertEqual(frame(view(), graph: graph).text(ofRow: 0), "42      ")
        XCTAssertEqual(frame(view(), graph: graph).text(ofRow: 0), "42      ")
    }

    func testBindingFromStateReadsAndWritesStorage() async {
        let graph = ViewGraph()
        let log = BindingLog()

        _ = frame(Counter(name: "c", log: log), graph: graph)
        let binding = log.last("c")
        binding?.wrappedValue = 3
        XCTAssertEqual(binding?.wrappedValue, 3)

        _ = frame(Counter(name: "c", log: log), graph: graph)
        XCTAssertEqual(log.last("c")?.wrappedValue, 3)
    }

    func testRootViewStateIsBound() async {
        let graph = ViewGraph()
        let log = BindingLog()

        _ = frame(Counter(name: "root", log: log), graph: graph)
        log.last("root")?.wrappedValue = 7
        XCTAssertEqual(frame(Counter(name: "root", log: log), graph: graph).text(ofRow: 0), "7       ")
    }

    func testPrimitiveViewStateIsBound() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view() -> some View {
            VStack { PrimitiveCounter(log: log) }
        }

        _ = frame(view(), graph: graph)
        log.last("primitive")?.wrappedValue = 12
        XCTAssertEqual(frame(view(), graph: graph).text(ofRow: 0), "12      ")
    }

    func testOptionalStateKeepsNil() async {
        let graph = ViewGraph()
        let log = OptionalLog()

        _ = frame(OptionalHolder(log: log), graph: graph)
        log.binding?.wrappedValue = nil
        XCTAssertEqual(frame(OptionalHolder(log: log), graph: graph).text(ofRow: 0), "nil     ")
    }

    // MARK: - 記憶域の割り当て

    func testViewsAtDifferentPositionsGetSeparateStorage() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view() -> some View {
            VStack {
                Counter(name: "a", log: log)
                Counter(name: "b", log: log)
            }
        }

        _ = frame(view(), graph: graph)
        log.last("a")?.wrappedValue = 1
        let buffer = frame(view(), graph: graph)

        XCTAssertEqual(buffer.text(ofRow: 0), "1       ")
        XCTAssertEqual(buffer.text(ofRow: 1), "0       ")
    }

    func testSameViewValueInTwoPlacesGetsSeparateStorage() async {
        let graph = ViewGraph()
        let log = BindingLog()
        let shared = Counter(name: "shared", log: log)
        func view() -> some View {
            VStack { shared; shared }
        }

        _ = frame(view(), graph: graph)
        log.bindings["shared"]?.first?.wrappedValue = 5
        let buffer = frame(view(), graph: graph)

        XCTAssertEqual(buffer.text(ofRow: 0), "5       ")
        XCTAssertEqual(buffer.text(ofRow: 1), "0       ")
    }

    func testKeyedViewKeepsStorageWhenReordered() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view(_ names: [String]) -> some View {
            VStack {
                for name in names {
                    Counter(name: name, log: log).id(name)
                }
            }
        }

        _ = frame(view(["x", "y"]), graph: graph)
        log.last("x")?.wrappedValue = 9
        let buffer = frame(view(["y", "x"]), graph: graph)

        XCTAssertEqual(buffer.text(ofRow: 0), "0       ")
        XCTAssertEqual(buffer.text(ofRow: 1), "9       ")
    }

    // MARK: - 記憶域の破棄

    func testStorageIsDiscardedWhenViewIsNotVisited() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view(showsCounter: Bool) -> some View {
            VStack {
                if showsCounter {
                    Counter(name: "c", log: log)
                }
            }
        }

        _ = frame(view(showsCounter: true), graph: graph)
        log.last("c")?.wrappedValue = 4
        _ = frame(view(showsCounter: false), graph: graph)

        XCTAssertEqual(frame(view(showsCounter: true), graph: graph).text(ofRow: 0), "0       ")
    }

    func testStorageIsKeptWhenViewIsOnlyMeasured() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view() -> some View {
            VStack {
                Text("top")
                Counter(name: "c", log: log)
            }
        }

        _ = frame(view(), graph: graph, height: 2)
        log.last("c")?.wrappedValue = 6
        _ = frame(view(), graph: graph, height: 1)

        XCTAssertEqual(frame(view(), graph: graph, height: 2).text(ofRow: 1), "6       ")
    }

    func testStorageIsDiscardedWhenTypeChangesAtSamePosition() async {
        let graph = ViewGraph()
        let log = BindingLog()

        _ = frame(VStack { Counter(name: "c", log: log) }, graph: graph)
        log.last("c")?.wrappedValue = 8
        let buffer = frame(HStack { Counter(name: "c", log: log) }, graph: graph)

        XCTAssertEqual(buffer.text(ofRow: 0), "0       ")
    }

    // MARK: - 結び付く前

    func testUnboundStateReadsInitialValueAndDropsWrites() async {
        let state = State(wrappedValue: 1)
        state.wrappedValue = 2
        XCTAssertEqual(state.wrappedValue, 1)

        let binding = state.projectedValue
        binding.wrappedValue = 3
        XCTAssertEqual(binding.wrappedValue, 1)
        XCTAssertEqual(state.wrappedValue, 1)
    }

    // MARK: - レイアウト

    func testLayoutTraitsFollowState() async {
        let graph = ViewGraph()
        let log = BindingLog()
        func view() -> some View {
            HStack {
                Expander(log: log)
                Text("|")
            }
        }

        XCTAssertEqual(frame(view(), graph: graph, width: 6, height: 1).text(ofRow: 0), "-|    ")
        log.last("expander")?.wrappedValue = 1
        XCTAssertEqual(frame(view(), graph: graph, width: 6, height: 1).text(ofRow: 0), "*****|")
    }
}
