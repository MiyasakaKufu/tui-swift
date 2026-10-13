import XCTest
@testable import TUIKit

@MainActor
final class ThemeTests: XCTestCase {

    /// 役割ごとに別の ``Style`` を置いた ``Theme``。
    private let custom = Theme(
        text: Style(foreground: .white),
        secondaryText: Style(foreground: .cyan),
        accent: Style(foreground: .magenta),
        selection: Style(foreground: .black, background: .yellow),
        border: Style(foreground: .blue),
        error: Style(foreground: .brightRed),
        warning: Style(foreground: .brightYellow)
    )

    /// `theme` を持つ `RenderContext` を渡して `view` を描いた `Buffer` を返す。
    ///
    /// - Parameters:
    ///   - view: 描く `View`。
    ///   - theme: `RenderContext.theme` が返す `Theme`。
    ///   - size: 画面の大きさ。
    /// - Returns: 描き終えた `Buffer`。
    private func render(_ view: some View, theme: Theme, size: Size = Size(width: 10, height: 3)) -> Buffer {
        var buffer = Buffer(size: size)
        let context = RenderContext(screen: buffer.bounds, ambiguousWidth: buffer.ambiguousWidth, theme: theme)
        view.render(into: &buffer, rect: buffer.bounds, context: context)
        return buffer
    }

    // MARK: - 受け渡し

    func testOptionsAndRenderContextUseStandardWhenOmitted() async {
        XCTAssertEqual(ApplicationOptions().theme, .standard)
        XCTAssertEqual(RenderContext(screen: .zero).theme, .standard)
    }

    func testRenderContextPassesThemeToChildren() async {
        let buffer = render(VStack { Text("a") }.padding(horizontal: 1), theme: custom)
        XCTAssertEqual(buffer[1, 0].style, custom.text)
    }

    func testApplicationContextPassesThemeToViews() async {
        let context = ApplicationContext(theme: custom)
        var buffer = Buffer(size: Size(width: 4, height: 1))
        context.draw({ Text("a") }, into: &buffer, ambiguousWidth: buffer.ambiguousWidth) { _ in }
        XCTAssertEqual(buffer[0, 0].style, custom.text)
    }

    // MARK: - Style の引数を省いた View

    func testStandardKeepsAppearanceOfOmittedStyles() async {
        let state = ListState()
        let list = render(ListView(items: ["a", "b"], state: state), theme: .standard)
        XCTAssertEqual(list[2, 0].style, Style(attributes: .reverse))
        XCTAssertEqual(list[2, 1].style, .plain)

        let field = render(TextField(state: TextFieldState(), placeholder: "x", showsCursor: false), theme: .standard)
        XCTAssertEqual(field[0, 0].style, Style(foreground: .brightBlack))

        let bar = render(ProgressBar(value: 0.5), theme: .standard)
        XCTAssertEqual(bar[0, 0].style, Style(foreground: .green))
        XCTAssertEqual(bar[9, 0].style, Style(foreground: .brightBlack))
    }

    func testTextUsesThemeText() async {
        XCTAssertEqual(render(Text("a"), theme: custom)[0, 0].style, custom.text)
    }

    func testTextAdjustmentsApplyOnThemeText() async {
        let buffer = render(Text("a").bold().background(.red), theme: custom)
        XCTAssertEqual(buffer[0, 0].style, Style(foreground: .white, background: .red, attributes: .bold))
    }

    func testListViewUsesThemeTextAndSelection() async {
        let buffer = render(ListView(items: ["a", "b"], state: ListState()), theme: custom)
        XCTAssertEqual(buffer[2, 0].style, custom.selection)
        XCTAssertEqual(buffer[9, 0].style, custom.selection)
        XCTAssertEqual(buffer[2, 1].style, custom.text)
    }

    func testTextFieldUsesThemeTextAndSecondaryText() async {
        let empty = render(TextField(state: TextFieldState(), placeholder: "x", showsCursor: false), theme: custom)
        XCTAssertEqual(empty[0, 0].style, custom.secondaryText)
        XCTAssertEqual(empty[1, 0].style, custom.text)

        let filled = render(TextField(state: TextFieldState(text: "y"), showsCursor: false), theme: custom)
        XCTAssertEqual(filled[0, 0].style, custom.text)
    }

    func testProgressBarUsesThemeAccentAndSecondaryText() async {
        let buffer = render(ProgressBar(value: 0.5), theme: custom)
        XCTAssertEqual(buffer[0, 0].style, custom.accent)
        XCTAssertEqual(buffer[9, 0].style, custom.secondaryText)
    }

    func testBorderAndDividerUseThemeBorder() async {
        let bordered = render(Text("a").border(title: "t"), theme: custom)
        XCTAssertEqual(bordered[0, 0].style, custom.border)
        XCTAssertEqual(bordered[2, 0].style, custom.border)
        XCTAssertEqual(bordered[1, 1].style, custom.text)

        XCTAssertEqual(render(Divider(), theme: custom)[0, 0].style, custom.border)
    }

    func testFillUsesThemeText() async {
        XCTAssertEqual(render(Fill("."), theme: custom)[0, 0].style, custom.text)
    }

    // MARK: - Style の引数を渡した View

    func testExplicitStylesIgnoreTheme() async {
        let red = Style(foreground: .red)
        let green = Style(foreground: .green)

        XCTAssertEqual(render(Text("a", style: red), theme: custom)[0, 0].style, red)
        XCTAssertEqual(render(Text("a").styled(red), theme: custom)[0, 0].style, red)
        XCTAssertEqual(render(Text("a", style: red).bold(), theme: custom)[0, 0].style, red.bold)

        let list = render(ListView(items: ["a", "b"], state: ListState(), style: red, selectedStyle: green), theme: custom)
        XCTAssertEqual(list[2, 0].style, green)
        XCTAssertEqual(list[2, 1].style, red)

        let field = render(
            TextField(state: TextFieldState(), placeholder: "x", style: red, placeholderStyle: green, showsCursor: false),
            theme: custom
        )
        XCTAssertEqual(field[0, 0].style, green)
        XCTAssertEqual(field[1, 0].style, red)

        let bar = render(ProgressBar(value: 0.5, filledStyle: red, emptyStyle: green), theme: custom)
        XCTAssertEqual(bar[0, 0].style, red)
        XCTAssertEqual(bar[9, 0].style, green)

        let bordered = render(Text("a").border(style: red, title: "t", titleStyle: green), theme: custom)
        XCTAssertEqual(bordered[0, 0].style, red)
        XCTAssertEqual(bordered[2, 0].style, green)

        XCTAssertEqual(render(Divider(style: red), theme: custom)[0, 0].style, red)
        XCTAssertEqual(render(Fill(".", style: red), theme: custom)[0, 0].style, red)
    }

    // MARK: - 用意した Theme

    func testMonochromeUsesOnlyDefaultColors() async {
        let monochrome = Theme.monochrome
        let styles = [
            monochrome.text, monochrome.secondaryText, monochrome.accent, monochrome.selection,
            monochrome.border, monochrome.error, monochrome.warning,
        ]
        for style in styles {
            XCTAssertEqual(style.foreground, .default)
            XCTAssertEqual(style.background, .default)
        }
    }

    func testOmittedInitializerArgumentsMatchStandard() async {
        let accent = Style(foreground: .magenta)
        var expected = Theme.standard
        expected.accent = accent
        XCTAssertEqual(Theme(accent: accent), expected)
    }
}
