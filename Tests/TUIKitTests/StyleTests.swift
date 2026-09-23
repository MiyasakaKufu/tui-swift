import XCTest
@testable import TUIKit

@MainActor
final class StyleTests: XCTestCase {

    func testIdenticalStylesProduceNoSequence() async {
        let style = Style(foreground: .red, attributes: .bold)
        XCTAssertEqual(style.sgrSequence(transitioningFrom: style), "")
    }

    func testAddingAttributeOnlyEmitsDifference() async {
        let from = Style(foreground: .red)
        let to = Style(foreground: .red, attributes: .bold)
        XCTAssertEqual(to.sgrSequence(transitioningFrom: from), "\u{1B}[1m")
    }

    func testRemovingAttributeResetsAndReapplies() async {
        let from = Style(foreground: .red, attributes: [.bold, .underline])
        let to = Style(foreground: .red, attributes: .underline)
        XCTAssertEqual(to.sgrSequence(transitioningFrom: from), "\u{1B}[0;4;31m")
    }

    func testBrightColorUsesHighIntensityCodes() async {
        XCTAssertEqual(Color.brightRed.foregroundParameters, ["91"])
        XCTAssertEqual(Color.brightRed.backgroundParameters, ["101"])
    }

    func testTrueColorParameters() async {
        let color = Color.rgb(r: 10, g: 20, b: 30)
        XCTAssertEqual(color.foregroundParameters, ["38", "2", "10", "20", "30"])
        XCTAssertEqual(color.backgroundParameters, ["48", "2", "10", "20", "30"])
    }

    func testXterm256Parameters() async {
        XCTAssertEqual(Color.xterm256(200).foregroundParameters, ["38", "5", "200"])
    }

    func testDefaultColorTransition() async {
        let from = Style(foreground: .red)
        let to = Style()
        XCTAssertEqual(to.sgrSequence(transitioningFrom: from), "\u{1B}[39m")
    }
}
