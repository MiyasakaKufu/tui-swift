import XCTest
@testable import TUIKit

@MainActor
final class OverlayTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> String {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        return buffer.debugText()
    }

    // MARK: - ZStack

    func testZStackDrawsLaterChildOnTop() async {
        let view = ZStack(horizontal: .leading, vertical: .top) {
            Fill(".")
            Text("ab")
        }
        XCTAssertEqual(render(view, width: 4, height: 2), "ab..\n....")
    }

    func testZStackCentersChildrenByDefault() async {
        let view = ZStack {
            Fill(".")
            Text("ab")
        }
        XCTAssertEqual(render(view, width: 4, height: 3), "....\n.ab.\n....")
    }

    func testZStackSizeIsLargestChild() async {
        let view = ZStack(children: [Text("abc"), Fill("#").frame(width: 2, height: 3)])
        XCTAssertEqual(view.sizeThatFits(Size(width: 10, height: 10)), Size(width: 3, height: 3))
    }

    func testZStackWithoutChildrenHasNoSize() async {
        let view = ZStack(children: [])
        XCTAssertEqual(view.sizeThatFits(Size(width: 10, height: 10)), .zero)
    }

    // MARK: - overlay

    func testOverlayKeepsSizeOfContent() async {
        let content = Text("ab")
        let view = content.overlay(Fill("#"))
        let proposal = Size(width: 10, height: 10)

        XCTAssertEqual(view.sizeThatFits(proposal), content.sizeThatFits(proposal))
        XCTAssertEqual(view.layoutTraits, content.layoutTraits)
    }

    func testOverlayDoesNotMoveSiblings() async {
        let view = VStack {
            Text("ab").overlay(Text("!"), horizontal: .trailing, vertical: .top)
            Text("cd")
        }
        XCTAssertEqual(render(view, width: 4, height: 2), "a!  \ncd  ")
    }

    func testOverlayStaysInsideContentRect() async {
        let view = VStack {
            Text("ab").overlay(Fill("#"))
            Text("cd")
        }
        XCTAssertEqual(render(view, width: 4, height: 2), "##  \ncd  ")
    }

    // MARK: - screenOverlay

    func testScreenOverlayCentersOnWholeBuffer() async {
        let view = VStack {
            Text("ab")
            Text("cd").screenOverlay(Text("#"))
        }
        XCTAssertEqual(render(view, width: 5, height: 5), "ab   \ncd   \n  #  \n     \n     ")
    }

    func testScreenOverlayKeepsSizeOfContent() async {
        let content = Text("ab")
        let view = content.screenOverlay(Fill("#"))
        let proposal = Size(width: 10, height: 10)

        XCTAssertEqual(view.sizeThatFits(proposal), content.sizeThatFits(proposal))
        XCTAssertEqual(view.layoutTraits, content.layoutTraits)
    }

    func testScreenOverlayAlignsToScreenEdge() async {
        let view = Text("ab").screenOverlay(Text("#"), horizontal: .trailing, vertical: .bottom)
        XCTAssertEqual(render(view, width: 3, height: 2), "ab \n  #")
    }

    // MARK: - 下を覆う

    func testBackgroundCoversContentBelow() async {
        let view = ZStack {
            Fill(".")
            Text("ok").padding(1).background(style: Style(background: .blue))
        }
        XCTAssertEqual(
            render(view, width: 6, height: 5),
            "......\n.    .\n. ok .\n.    .\n......"
        )
    }

    // MARK: - 全角文字

    func testOverlayOnWideCharacterHeadKeepsColumns() async {
        let view = ZStack(horizontal: .leading, vertical: .top) {
            Text("あいう")
            Text("X")
        }
        XCTAssertEqual(render(view, width: 6, height: 1), "X いう")
    }

    func testOverlayOnWideCharacterContinuationKeepsColumns() async {
        let view = ZStack(horizontal: .leading, vertical: .top) {
            Text("あい")
            Text("X").padding(horizontal: 1)
        }
        XCTAssertEqual(render(view, width: 6, height: 1), " Xい  ")
    }

    func testDialogOverWideCharactersKeepsRowWidth() async {
        let view = ZStack {
            Fill("あ")
            Text("確認").padding(1).background(style: Style(background: .blue))
        }
        var buffer = Buffer(size: Size(width: 9, height: 5))
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)

        for y in 0..<buffer.size.height {
            XCTAssertEqual(DisplayWidth.width(of: buffer.text(ofRow: y)), 9, "行 \(y) の表示幅")
        }
    }
}
