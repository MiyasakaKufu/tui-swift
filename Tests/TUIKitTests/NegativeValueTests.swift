import XCTest
@testable import TUIKit

/// 負の余白・サイズを渡しても領域の外に描かず、クラッシュもしないことを確かめる。
@MainActor
final class NegativeValueTests: XCTestCase {

    func testSizeClampsNegativeAssignment() async {
        var size = Size(width: 4, height: 2)
        size.width = -1
        size.height = -5
        XCTAssertEqual(size, .zero)
        XCTAssertTrue(size.isEmpty)
    }

    func testEdgeInsetsClampNegativeValues() async {
        let insets = EdgeInsets(top: -1, leading: -2, bottom: -3, trailing: -4)
        XCTAssertEqual(insets, .zero)

        var mutated = EdgeInsets(all: 2)
        mutated.leading = -1
        XCTAssertEqual(mutated.leading, 0)
    }

    func testRectInsetByNegativeAmountDoesNotGrow() async {
        let rect = Rect(x: 1, y: 1, width: 3, height: 1)
        XCTAssertEqual(rect.inset(by: -1), rect)
    }

    func testNegativePaddingDoesNotDrawOutsideRect() async {
        var buffer = Buffer(size: Size(width: 5, height: 3))
        Text("abc").padding(-1).render(into: &buffer, rect: Rect(x: 1, y: 1, width: 3, height: 1))

        XCTAssertEqual(buffer.text(ofRow: 0), "     ")
        XCTAssertEqual(buffer.text(ofRow: 1), " abc ")
        XCTAssertEqual(buffer.text(ofRow: 2), "     ")
    }

    func testNegativeFrameHeightDoesNotCrash() async {
        var buffer = Buffer(size: Size(width: 8, height: 3))
        let state = ListState()
        ListView(items: ["a", "b"], state: state)
            .frame(height: -1)
            .render(into: &buffer, rect: Rect(x: 0, y: 0, width: 8, height: 3))

        XCTAssertEqual(buffer.debugText(), ["        ", "        ", "        "].joined(separator: "\n"))
    }

    func testNegativeFrameWidthDrawsNothing() async {
        var buffer = Buffer(size: Size(width: 5, height: 1))
        Text("abc")
            .frame(width: -3)
            .render(into: &buffer, rect: Rect(x: 0, y: 0, width: 5, height: 1))

        XCTAssertEqual(buffer.text(ofRow: 0), "     ")
    }
}
