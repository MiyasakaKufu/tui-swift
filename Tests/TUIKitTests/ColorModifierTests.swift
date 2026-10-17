import XCTest
@testable import TUIKit

@MainActor
final class ColorModifierTests: XCTestCase {

    private func render(_ view: any View, width: Int, height: Int) -> Buffer {
        var buffer = Buffer(size: Size(width: width, height: height))
        let bounds = buffer.bounds
        view.renderAsRoot(into: &buffer, rect: bounds)
        return buffer
    }

    // MARK: - foregroundStyle

    func testForegroundStyleReachesTextInside() async {
        let view = VStack {
            Text("a")
            Text("b")
        }
        .foregroundStyle(.red)
        let buffer = render(view, width: 1, height: 2)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .red))
        XCTAssertEqual(buffer[0, 1].style, Style(foreground: .red))
    }

    func testInnerForegroundStyleWins() async {
        let view = VStack {
            Text("a").foregroundStyle(.green)
            Text("b").foregroundStyle(.blue)
        }
        .foregroundStyle(.red)
        let buffer = render(view, width: 1, height: 2)
        XCTAssertEqual(buffer[0, 0].style.foreground, .green)
        XCTAssertEqual(buffer[0, 1].style.foreground, .blue)
    }

    func testSecondaryAddsDimToPrimaryWhenNotGiven() async {
        let view = VStack {
            Text("a").foregroundStyle(.secondary)
        }
        .foregroundStyle(.red)
        XCTAssertEqual(render(view, width: 1, height: 1)[0, 0].style, Style(foreground: .red, attributes: .dim))
    }

    func testSecondaryUsesGivenColor() async {
        let view = Text("a").foregroundStyle(.secondary).foregroundStyle(.red, .brightBlack)
        XCTAssertEqual(render(view, width: 1, height: 1)[0, 0].style, Style(foreground: .brightBlack))
    }

    func testHierarchicalForegroundStyleOnContainerShiftsLevel() async {
        let view = VStack {
            Text("a")
        }
        .foregroundStyle(.secondary)
        .foregroundStyle(.red, .brightBlack)
        XCTAssertEqual(render(view, width: 1, height: 1)[0, 0].style, Style(foreground: .brightBlack))
    }

    func testTextAttributesAddToForegroundStyle() async {
        let view = Text("a").bold().foregroundStyle(.red)
        XCTAssertEqual(render(view, width: 1, height: 1)[0, 0].style, Style(foreground: .red, attributes: .bold))
    }

    func testTextWithoutForegroundStyleUsesTerminalDefault() async {
        XCTAssertEqual(render(Text("a"), width: 1, height: 1)[0, 0].style, .plain)
    }

    // MARK: - background

    func testBackgroundReachesCellsWrittenInside() async {
        let view = VStack {
            Text("ab")
            Text("c").foregroundStyle(.red)
        }
        .background(.blue)
        let buffer = render(view, width: 2, height: 2)
        XCTAssertEqual(buffer[0, 0].style.background, .blue)
        XCTAssertEqual(buffer[0, 1].style, Style(foreground: .red, background: .blue))
        XCTAssertEqual(buffer[1, 1].style.background, .blue)
    }

    func testBorderUsesBackgroundOutside() async {
        let view = Text("a").border(.single, color: .yellow).background(.blue)
        let buffer = render(view, width: 3, height: 3)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .yellow, background: .blue))
        XCTAssertEqual(buffer[1, 1].style.background, .blue)
    }

    func testBorderWithoutColorUsesPrimary() async {
        let view = Text("a").border(.single, title: "T").foregroundStyle(.red)
        XCTAssertEqual(render(view, width: 5, height: 3)[0, 0].style, Style(foreground: .red))
    }

    // MARK: - tint

    func testProgressBarUsesTintAndSecondary() async {
        let view = ProgressBar(value: 0.5).tint(.green).foregroundStyle(.white, .brightBlack)
        let buffer = render(view, width: 4, height: 1)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .green))
        XCTAssertEqual(buffer[3, 0].style, Style(foreground: .brightBlack))
    }

    func testProgressBarWithoutTintUsesPrimary() async {
        let view = ProgressBar(value: 0.5).foregroundStyle(.white)
        let buffer = render(view, width: 4, height: 1)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .white))
        XCTAssertEqual(buffer[3, 0].style, Style(foreground: .white, attributes: .dim))
    }

    func testListViewReversesTintOnSelectedRow() async {
        let view = ListView(items: ["a", "b"], state: ListState())
            .tint(.green)
            .background(.blue)
        let buffer = render(view, width: 4, height: 2)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .green, background: .blue, attributes: .reverse))
        XCTAssertEqual(buffer[3, 0].style, Style(foreground: .green, background: .blue, attributes: .reverse))
        XCTAssertEqual(buffer[0, 1].style, Style(background: .blue))
    }

    func testListViewWithoutTintReversesPrimary() async {
        let view = ListView(items: ["a"], state: ListState())
        XCTAssertEqual(render(view, width: 3, height: 1)[0, 0].style, Style(attributes: .reverse))
    }

    func testTintNilFallsBackToPrimary() async {
        let view = ProgressBar(value: 1).tint(nil).foregroundStyle(.red).tint(.green)
        XCTAssertEqual(render(view, width: 2, height: 1)[0, 0].style, Style(foreground: .red))
    }

    // MARK: - TextField

    func testTextFieldPlaceholderUsesSecondary() async {
        let view = TextField(state: TextFieldState(), placeholder: "x").foregroundStyle(.white, .brightBlack)
        XCTAssertEqual(render(view, width: 3, height: 1)[0, 0].style, Style(foreground: .brightBlack))
    }

    func testTextFieldTextUsesPrimary() async {
        let view = TextField(state: TextFieldState(text: "x"), showsCursor: false).foregroundStyle(.white, .brightBlack)
        XCTAssertEqual(render(view, width: 3, height: 1)[0, 0].style, Style(foreground: .white))
    }

    // MARK: - 届く範囲

    func testSheetContentUsesColorsOutsideSheet() async {
        let view = Text("a")
            .sheet(isPresented: Binding(get: { true }, set: { _ in })) {
                Text("b")
            }
            .foregroundStyle(.red)
        let buffer = render(view, width: 3, height: 3)
        XCTAssertEqual(buffer[1, 1].character, "b")
        XCTAssertEqual(buffer[1, 1].style.foreground, .red)
    }
}
