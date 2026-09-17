import XCTest
@testable import TUIKit

/// 型注釈と戻り値が食い違えばビルドが通らないので、検査の本体はコンパイル時に行われる。
final class ModifierGenericsTests: XCTestCase {

    func testModifiersReturnConcreteTypes() {
        let padded: PaddingView<Text> = Text("x").padding(1)
        let bordered: BorderView<Text> = Text("x").border(.ascii, title: "T")
        let background: BackgroundView<Text> = Text("x").background(.red)
        let framed: FrameView<Fill> = Fill("#").frame(width: 2, height: 1)
        let flexed: FlexibleView<Fill> = Fill("#").flexible(horizontal: 2, vertical: 3)
        let aligned: AlignedView<Text> = Text("x").aligned()

        XCTAssertEqual(padded.insets, EdgeInsets(all: 1))
        XCTAssertEqual(bordered.title, "T")
        XCTAssertEqual(background.style.background, .red)
        XCTAssertEqual(framed.width, 2)
        XCTAssertEqual(flexed.traits, LayoutTraits(horizontalFlex: 2, verticalFlex: 3))
        XCTAssertEqual(aligned.horizontal, .center)
    }

    func testChainedModifiersKeepContentType() {
        let view: BorderView<PaddingView<Text>> = Text("x").padding(1).border(.ascii)

        XCTAssertEqual(view.content.content.content, "x")
    }

    func testPaddingHorizontalVerticalReturnsConcreteType() {
        let view: PaddingView<Text> = Text("x").padding(horizontal: 2, vertical: 1)
        XCTAssertEqual(view.insets, EdgeInsets(horizontal: 2, vertical: 1))
    }
}
