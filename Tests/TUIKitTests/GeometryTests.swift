import XCTest
@testable import TUIKit

@TUIActor
final class GeometryTests: XCTestCase {

    func testSizeClampsNegativeValues() async {
        let size = Size(width: -3, height: 5)
        XCTAssertEqual(size.width, 0)
        XCTAssertEqual(size.height, 5)
    }

    func testRectIntersection() async {
        let a = Rect(x: 0, y: 0, width: 10, height: 10)
        let b = Rect(x: 5, y: 5, width: 10, height: 10)
        XCTAssertEqual(a.intersection(b), Rect(x: 5, y: 5, width: 5, height: 5))
    }

    func testRectIntersectionWithoutOverlapIsEmpty() async {
        let a = Rect(x: 0, y: 0, width: 4, height: 4)
        let b = Rect(x: 10, y: 10, width: 4, height: 4)
        XCTAssertTrue(a.intersection(b).isEmpty)
    }

    func testRectInset() async {
        let rect = Rect(x: 2, y: 3, width: 10, height: 6)
        let inner = rect.inset(by: 1)
        XCTAssertEqual(inner, Rect(x: 3, y: 4, width: 8, height: 4))
    }

    func testRectInsetLargerThanRect() async {
        let rect = Rect(x: 0, y: 0, width: 2, height: 2)
        XCTAssertTrue(rect.inset(by: 5).isEmpty)
    }

    func testAlignmentOffsets() async {
        XCTAssertEqual(HorizontalAlignment.leading.offset(content: 4, available: 10), 0)
        XCTAssertEqual(HorizontalAlignment.center.offset(content: 4, available: 10), 3)
        XCTAssertEqual(HorizontalAlignment.trailing.offset(content: 4, available: 10), 6)
        XCTAssertEqual(VerticalAlignment.bottom.offset(content: 12, available: 10), 0)
    }
}
