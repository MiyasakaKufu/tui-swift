import XCTest
@testable import TUIKit

/// 測られた経路と描かれた経路を、子の名前ごとに記録する。
@MainActor
private final class PathLog {
    /// 測られたときの経路。
    var measured: [String: Set<ViewPath>] = [:]
    /// 描かれたときの経路。描かれた順に並ぶ。
    var rendered: [String: [ViewPath]] = [:]
}

/// 渡された文脈の経路を記録するビュー。
private struct PathProbe: View {
    /// 記録に使う名前。
    let name: String
    /// 記録先。
    let log: PathLog
    /// 余白の分配に関する性質。
    var layoutTraits: LayoutTraits = .fixed

    /// 経路を記録し、1 桁・1 行を希望する。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 1 桁・1 行のサイズ。
    func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        log.measured[name, default: []].insert(context.path)
        return Size(width: 1, height: 1)
    }

    /// 経路を記録する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
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
            PathProbe(name: "flexible", log: log, layoutTraits: .flexible)
            HStack {
                PathProbe(name: "left", log: log)
                PathProbe(name: "right", log: log, layoutTraits: .flexible)
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
            XCTAssertEqual(measured.count, 1, "\(name) が複数の経路で測られた")
            XCTAssertEqual(rendered.count, 1, "\(name) の描画が 1 回でない")
            XCTAssertEqual(Set(rendered), measured, "\(name) の経路がレイアウトと描画で違う")
        }
        let paths = names.compactMap { log.rendered[$0]?.first }
        XCTAssertEqual(Set(paths).count, names.count, "別の子に同じ経路が振られた")
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
            PathProbe(name: "b", log: log, layoutTraits: .flexible)
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
