import XCTest
@testable import TUIKit

/// `PathProbe` のメソッドが受け取った `RenderContext.path` を、`PathProbe.name` ごとに記録するクラス。
@MainActor
private final class PathLog {
    /// `PathProbe.sizeThatFits(_:context:)` が受け取った `RenderContext.path`。
    var measured: [String: Set<ViewPath>] = [:]
    /// `PathProbe.render(into:rect:context:)` が受け取った `RenderContext.path`。呼び出された順に並ぶ。
    var rendered: [String: [ViewPath]] = [:]
    /// `PathProbe.layoutTraits(context:)` が受け取った `RenderContext.path`。
    var traitsRead: [String: Set<ViewPath>] = [:]
}

/// 受け取った `RenderContext.path` を `PathLog` に記録する `View`。
private struct PathProbe: PrimitiveView {
    /// 記録に使う名前。
    let name: String
    /// 記録先。
    let log: PathLog
    /// `PathProbe.layoutTraits(context:)` が返す `LayoutTraits`。
    var traits: LayoutTraits = .fixed

    /// `RenderContext.path` を記録し、`traits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `traits`。
    func layoutTraits(context: RenderContext) -> LayoutTraits {
        log.traitsRead[name, default: []].insert(context.path)
        return traits
    }

    /// `RenderContext.path` を記録し、幅 1・高さ 1 の `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 幅 1・高さ 1 の `Size`。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        log.measured[name, default: []].insert(context.path)
        return Size(width: 1, height: 1)
    }

    /// `RenderContext.path` を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        log.rendered[name, default: []].append(context.path)
    }
}

@MainActor
final class RenderContextTests: XCTestCase {

    private func draw(_ view: some View, width: Int, height: Int) {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.renderAsRoot(into: &buffer, rect: bounds)
    }

    func testSameChildGetsSamePathInLayoutAndRender() async {
        let log = PathLog()
        let view = VStack {
            PathProbe(name: "fixed", log: log)
            PathProbe(name: "flexible", log: log, traits: .flexible)
            HStack {
                PathProbe(name: "left", log: log)
                PathProbe(name: "right", log: log, traits: .flexible)
            }
            .padding(1)
            .border()
            ZStack {
                PathProbe(name: "back", log: log)
                PathProbe(name: "front", log: log)
            }
            PathProbe(name: "content", log: log)
                .overlay(PathProbe(name: "overlay", log: log))
                .aligned()
        }
        .screenOverlay(PathProbe(name: "dialog", log: log))

        draw(view, width: 20, height: 20)

        let names = ["fixed", "flexible", "left", "right", "back", "front", "content", "overlay", "dialog"]
        for name in names {
            let measured = log.measured[name] ?? []
            let rendered = log.rendered[name] ?? []
            XCTAssertEqual(measured.count, 1, "\(name) の `View.sizeThatFits(_:context:)` が複数の `ViewPath` で呼び出された")
            XCTAssertEqual(rendered.count, 1, "\(name) の `View.render(into:rect:context:)` の呼び出しが 1 回でない")
            XCTAssertEqual(Set(rendered), measured, "\(name) の `ViewPath` が `View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` で違う")
        }
        let paths = names.compactMap { log.rendered[$0]?.first }
        XCTAssertEqual(Set(paths).count, names.count, "別の `PathProbe` に同じ `ViewPath` が振られた")
    }

    func testTraitsAreReadAtSamePathAsLayoutAndRender() async {
        let log = PathLog()
        let view = VStack {
            PathProbe(name: "fixed", log: log)
            HStack {
                PathProbe(name: "left", log: log)
                PathProbe(name: "right", log: log, traits: .flexible)
            }
            .padding(1)
            .border()
            .frame(height: 3)
            ZStack {
                PathProbe(name: "back", log: log)
            }
        }
        .screenOverlay(PathProbe(name: "dialog", log: log))

        draw(view, width: 20, height: 20)

        for name in ["fixed", "left", "right", "back", "dialog"] {
            let read = log.traitsRead[name] ?? []
            XCTAssertEqual(read.count, 1, "\(name) の `View.layoutTraits(context:)` が 1 つの `ViewPath` で呼び出されていない")
            XCTAssertEqual(read, log.measured[name], "\(name) の `View.layoutTraits(context:)` が受け取った `ViewPath` が、`View.sizeThatFits(_:context:)` が受け取った `ViewPath` と違う")
        }
    }

    func testChildMeasuredButNotDrawnKeepsPathWhenDrawnLater() async {
        let log = PathLog()
        let view = VStack {
            PathProbe(name: "first", log: log)
            PathProbe(name: "second", log: log)
        }

        draw(view, width: 4, height: 1)
        XCTAssertNil(log.rendered["second"])
        let measured = log.measured["second"] ?? []
        XCTAssertEqual(measured.count, 1)

        draw(view, width: 4, height: 2)
        XCTAssertEqual(log.rendered["second"].map { Set($0) }, measured)
    }

    func testPathDoesNotDependOnFrame() async {
        let log = PathLog()
        let view = HStack {
            PathProbe(name: "a", log: log)
            PathProbe(name: "b", log: log, traits: .flexible)
        }

        draw(view, width: 10, height: 1)
        draw(view, width: 3, height: 2)

        XCTAssertEqual(log.rendered["a"]?.count, 2)
        XCTAssertEqual(Set(log.rendered["a"] ?? []).count, 1)
        XCTAssertEqual(Set(log.rendered["b"] ?? []).count, 1)
        XCTAssertEqual(log.measured["b"]?.count, 1)
    }

    func testScreenOverlayPlacesOverlayOnScreenFromContext() async {
        let view = Text("ab")
            .frame(width: 2, height: 1)
            .screenOverlay(Text("x"), horizontal: .trailing, vertical: .bottom)
        var buffer = Buffer(size: Size(width: 4, height: 3))
        let context = RenderContext(screen: Rect(x: 0, y: 0, width: 3, height: 2))
        view.render(into: &buffer, rect: Rect(x: 0, y: 0, width: 2, height: 1), context: context)

        XCTAssertEqual(buffer.debugText(), "ab  \n  x \n    ")
    }
}
