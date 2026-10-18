import XCTest
@testable import TUIKit

/// `View.onHover(perform:)` のクロージャに渡された値を、渡された順に記録するもの。
@MainActor
private final class HoverLog {
    /// `名前:値` の形で、渡された順に並べたもの。
    private(set) var entries: [String] = []

    /// `View.onHover(perform:)` に渡すクロージャを返す。
    ///
    /// - Parameters:
    ///   - name: 記録に付ける名前。
    /// - Returns: 渡された値を `name` とともに記録するクロージャ。
    func record(_ name: String) -> @MainActor (Bool) -> Void {
        { [unowned self] isHovered in entries.append("\(name):\(isHovered)") }
    }

    /// 記録を空にする。
    func clear() {
        entries = []
    }
}

/// マウスポインタが上にあるかで、表示する文字列を変える `View`。
private struct HoverLabel: View {
    @State private var isHovered = false

    var body: some View {
        Text(isHovered ? "on" : "off")
            .onHover { isHovered = $0 }
    }
}

@MainActor
final class HoverTests: XCTestCase {
    private let log = HoverLog()

    // MARK: - 入ったときと出たとき

    func testMovingOntoAndAwayCallsTrueThenFalseOnce() async {
        let harness = FocusHarness(size: Size(width: 4, height: 2)) {
            VStack(spacing: 0) {
                Text("a").onHover(perform: self.log.record("a"))
                Text("b")
            }
        }

        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 0, y: 1))

        XCTAssertEqual(log.entries, ["a:true", "a:false"])
    }

    func testAssignmentInActionIsDrawn() async {
        let harness = FocusHarness(size: Size(width: 4, height: 1)) { HoverLabel() }
        XCTAssertEqual(harness.line(0), "off ")

        harness.move(to: Point(x: 0, y: 0))

        XCTAssertEqual(harness.line(0), "on  ")
    }

    func testEnclosingOnHoverIsAlsoHoveredAndExitsRunInnerFirst() async {
        let harness = FocusHarness(size: Size(width: 4, height: 3)) {
            VStack(spacing: 0) {
                Text("a").onHover(perform: self.log.record("inner"))
                Text("b")
            }
            .onHover(perform: self.log.record("outer"))
        }

        harness.move(to: Point(x: 0, y: 0))
        XCTAssertEqual(log.entries, ["outer:true", "inner:true"])
        log.clear()

        harness.move(to: Point(x: 0, y: 1))
        XCTAssertEqual(log.entries, ["inner:false"])
        log.clear()

        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 0, y: 2))
        XCTAssertEqual(log.entries, ["inner:true", "inner:false", "outer:false"])
    }

    func testMovingBetweenViewsCallsFalseBeforeTrue() async {
        let harness = FocusHarness(size: Size(width: 4, height: 2)) {
            VStack(spacing: 0) {
                Text("a").onHover(perform: self.log.record("a"))
                Text("b").onHover(perform: self.log.record("b"))
            }
        }

        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 0, y: 1))

        XCTAssertEqual(log.entries, ["a:true", "a:false", "b:true"])
    }

    // MARK: - 重なり

    func testViewCoveredByOverlayIsNotHovered() async {
        let harness = FocusHarness(size: Size(width: 4, height: 1)) {
            Text("aaaa")
                .onHover(perform: self.log.record("below"))
                .overlay(
                    Text("x").onHover(perform: self.log.record("above")),
                    horizontal: .leading,
                    vertical: .top
                )
        }

        harness.move(to: Point(x: 0, y: 0))
        XCTAssertEqual(log.entries, ["above:true"])
        log.clear()

        harness.move(to: Point(x: 2, y: 0))
        XCTAssertEqual(log.entries, ["above:false", "below:true"])
    }

    func testCellsNotWrittenAreNotHoveredLikeClicks() async {
        let harness = FocusHarness(size: Size(width: 4, height: 3)) {
            VStack(spacing: 1) {
                Text("a")
                Text("b")
            }
            .onHover(perform: self.log.record("stack"))
        }

        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 0, y: 1))
        harness.move(to: Point(x: 0, y: 2))

        XCTAssertEqual(log.entries, ["stack:true", "stack:false", "stack:true"])
    }

    // MARK: - マウスポインタを動かさずに配置が変わったとき

    func testLayoutChangeAloneDoesNotCallAction() async {
        var showsFirst = true
        let harness = FocusHarness(size: Size(width: 4, height: 2)) {
            VStack(spacing: 0) {
                if showsFirst {
                    Text("a").onHover(perform: self.log.record("a"))
                }
                // `View.id(_:)` を外したくなるが、外すと `showsFirst` を切り替えたときに "b" の `ViewPath` が "a" のものと同じになり（#143）、"a" と同じ `ViewNode` として扱われて、どちらのクロージャも呼び出されない。
                Text("b").onHover(perform: self.log.record("b")).id("b")
            }
        }
        harness.move(to: Point(x: 0, y: 0))
        log.clear()

        showsFirst = false
        let countBefore = harness.presentCount
        harness.draw()
        XCTAssertEqual(log.entries, [])
        XCTAssertEqual(harness.presentCount - countBefore, 1)

        harness.move(to: Point(x: 0, y: 0))
        XCTAssertEqual(log.entries, ["a:false", "b:true"])
    }

    func testViewVisitedButNotDrawnCallsFalseOnNextMouseEvent() async {
        var height = 2
        let harness = FocusHarness(size: Size(width: 4, height: 2)) {
            VStack(spacing: 0) {
                Text("a")
                Text("b").onHover(perform: self.log.record("b"))
            }
            .frame(height: height)
        }
        harness.move(to: Point(x: 0, y: 1))
        log.clear()

        height = 1
        harness.draw()
        harness.move(to: Point(x: 0, y: 1))

        XCTAssertEqual(log.entries, ["b:false"])
    }

    // MARK: - View.sheet(isPresented:content:)

    func testViewsBehindSheetCallFalseOnNextMouseEventAndOnlyInsideIsHovered() async {
        var isPresented = false
        let harness = FocusHarness(size: Size(width: 20, height: 5)) {
            Text("back")
                .onHover(perform: self.log.record("back"))
                .sheet(isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })) {
                    Text("front").onHover(perform: self.log.record("front"))
                }
        }
        harness.move(to: Point(x: 0, y: 0))
        log.clear()

        isPresented = true
        harness.draw()
        XCTAssertEqual(log.entries, [])

        harness.move(to: Point(x: 0, y: 0))
        harness.move(to: Point(x: 7, y: 2))
        harness.move(to: Point(x: 0, y: 0))
        XCTAssertEqual(log.entries, ["back:false", "front:true", "front:false"])
        log.clear()

        isPresented = false
        harness.draw()
        harness.move(to: Point(x: 0, y: 0))
        XCTAssertEqual(log.entries, ["back:true"])
    }

    // MARK: - ApplicationOptions.mouseTracking

    func testDisabledHoverNeverCallsAction() async {
        let harness = FocusHarness(size: Size(width: 4, height: 1)) {
            Text("a").onHover(perform: self.log.record("a"))
        }
        harness.context.hover.isEnabled = false

        harness.move(to: Point(x: 0, y: 0))
        harness.click(at: Point(x: 0, y: 0))

        XCTAssertEqual(log.entries, [])
    }
}
