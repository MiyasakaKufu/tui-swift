import XCTest
@testable import TUIKit

@TUIActor
final class LayoutTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    func testTabIsNotDroppedFromText() {
        XCTAssertEqual(render(Text("a\tb"), width: 10, height: 1), "a   b     ")
    }

    func testTabInsideLineAlignsToTabStop() {
        XCTAssertEqual(render(Text("ab\tc\td"), width: 12, height: 1), "ab  c   d   ")
    }

    func testTextTabSizeIsConfigurable() {
        XCTAssertEqual(render(Text("a\tb").tabStops(every: 8), width: 10, height: 1), "a       b ")
    }

    func testVStackStacksChildrenVertically() {
        let view = VStack {
            Text("a")
            Text("b")
        }
        XCTAssertEqual(render(view, width: 2, height: 3), "a \nb \n  ")
    }

    func testVStackSpacing() {
        let view = VStack(spacing: 1) {
            Text("a")
            Text("b")
        }
        XCTAssertEqual(render(view, width: 1, height: 3), "a\n \nb")
    }

    func testVStackSpacerPushesToEdges() {
        let view = VStack {
            Text("a")
            Spacer()
            Text("b")
        }
        XCTAssertEqual(render(view, width: 1, height: 4), "a\n \n \nb")
    }

    func testHStackSpacerPushesToEdges() {
        let view = HStack {
            Text("a")
            Spacer()
            Text("b")
        }
        XCTAssertEqual(render(view, width: 5, height: 1), "a   b")
    }

    func testVStackAlignment() {
        let view = VStack(alignment: .trailing) {
            Text("ab")
            Text("c")
        }
        XCTAssertEqual(render(view, width: 3, height: 2), " ab\n  c")
    }

    func testStackClipsOverflow() {
        let view = VStack {
            Text("a")
            Text("b")
            Text("c")
        }
        XCTAssertEqual(render(view, width: 1, height: 2), "a\nb")
    }

    func testBorderDrawsFrameAroundContent() {
        let view = Text("hi").border(.ascii)
        XCTAssertEqual(render(view, width: 6, height: 3), "+----+\n|hi  |\n+----+")
    }

    func testBorderWithTitle() {
        let view = EmptyView().border(.ascii, title: "T")
        XCTAssertEqual(render(view, width: 8, height: 3), "+ T ---+\n|      |\n+------+")
    }

    func testBorderTitleExpandsTabs() {
        let view = EmptyView().border(.ascii, title: "a\tb")
        XCTAssertEqual(render(view, width: 10, height: 3), "+ a  b --+\n|        |\n+--------+")
    }

    func testPaddingShiftsContent() {
        let view = Text("x").padding(1)
        XCTAssertEqual(render(view, width: 3, height: 3), "   \n x \n   ")
    }

    func testFrameLimitsSize() {
        let view = Fill("#").frame(width: 2, height: 1)
        XCTAssertEqual(render(view, width: 4, height: 2), "##  \n    ")
    }

    func testAlignedCentersContent() {
        let view = Text("x").aligned(horizontal: .center, vertical: .center)
        XCTAssertEqual(render(view, width: 3, height: 3), "   \n x \n   ")
    }

    func testFlexibleWeightsSplitRemainingSpace() {
        let view = HStack {
            Fill("a").flexible(horizontal: 1, vertical: 1)
            Fill("b").flexible(horizontal: 3, vertical: 1)
        }
        XCTAssertEqual(render(view, width: 8, height: 1), "aabbbbbb")
    }

    func testDividerFillsWidth() {
        let view = Divider(character: "-")
        XCTAssertEqual(render(view, width: 4, height: 1), "----")
    }

    func testTextWrapsWithinStack() {
        let view = VStack {
            Text("hello world", wrap: .word)
        }
        XCTAssertEqual(render(view, width: 5, height: 2), "hello\nworld")
    }

    func testSizeThatFitsForVStack() {
        let view = VStack(spacing: 1) {
            Text("abc")
            Text("de")
        }
        let size = view.sizeThatFits(Size(width: 10, height: 10))
        XCTAssertEqual(size, Size(width: 3, height: 3))
    }
}
