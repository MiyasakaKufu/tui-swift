import XCTest
@testable import TUIKit

/// `body` だけを書いた表示専用のコンポーネント。
private final class DisplayOnlyComponent: Component {
    var body: some View {
        Text("こんにちは")
    }
}

/// `@main` を付けずに起動できる形だけ確かめるためのアプリ。
private final class MinimalApp: TerminalApp {
    static var options: ApplicationOptions { ApplicationOptions(mouseTracking: .buttons) }

    var body: some View {
        VStack(spacing: 1) {
            Text("上")
            Text("下")
        }
    }
}

@MainActor
final class ComponentTests: XCTestCase {

    func testDefaultHandleIgnoresEvents() async {
        let component = DisplayOnlyComponent()
        XCTAssertEqual(component.handle(.key(KeyEvent(.up))), .ignored)
        XCTAssertEqual(component.handle(.resize(Size(width: 10, height: 4))), .ignored)
    }

    func testDefaultCursorPositionIsNil() async {
        XCTAssertNil(DisplayOnlyComponent().cursorPosition)
    }

    func testBodyRendersThroughStaticType() async {
        var buffer = Buffer(size: Size(width: 10, height: 1))
        DisplayOnlyComponent().body.render(into: &buffer, rect: buffer.bounds)
        XCTAssertEqual(buffer.text(ofRow: 0), "こんにちは")
    }

    func testDefaultOptions() async {
        let options = ApplicationOptions.default
        XCTAssertTrue(options.usesAlternateScreen)
        XCTAssertEqual(options.mouseTracking, .disabled)
        XCTAssertTrue(options.usesBracketedPaste)
        XCTAssertNil(options.frameInterval)
        XCTAssertTrue(options.quitsOnControlC)
        XCTAssertTrue(options.suspendsOnControlZ)
    }

    func testQuitsOnUnhandledControlC() async {
        let options = ApplicationOptions.default
        XCTAssertTrue(options.quits(onUnhandled: .key(KeyEvent(.character("c"), modifiers: .control))))
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("c")))))
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("q"), modifiers: .control))))
        XCTAssertFalse(options.quits(onUnhandled: .resize(Size(width: 1, height: 1))))
    }

    func testQuitsOnControlCCanBeDisabled() async {
        let options = ApplicationOptions(quitsOnControlC: false)
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("c"), modifiers: .control))))
    }

    func testSuspendsOnUnhandledControlZ() async {
        let options = ApplicationOptions.default
        XCTAssertTrue(options.suspends(onUnhandled: .key(KeyEvent(.character("z"), modifiers: .control))))
        XCTAssertFalse(options.suspends(onUnhandled: .key(KeyEvent(.character("z")))))
        XCTAssertFalse(options.suspends(onUnhandled: .key(KeyEvent(.character("c"), modifiers: .control))))
        XCTAssertFalse(options.suspends(onUnhandled: .resize(Size(width: 1, height: 1))))
    }

    func testSuspendsOnControlZCanBeDisabled() async {
        let options = ApplicationOptions(suspendsOnControlZ: false)
        XCTAssertFalse(options.suspends(onUnhandled: .key(KeyEvent(.character("z"), modifiers: .control))))
    }

    func testTerminalAppProvidesDefaultOptions() async {
        XCTAssertEqual(MinimalApp.options.mouseTracking, .buttons)
        XCTAssertTrue(DefaultOptionApp.options.quitsOnControlC)
        XCTAssertEqual(DefaultOptionApp.options.mouseTracking, .disabled)
    }
}

/// `options` を書かないアプリ。既定値が使われる。
private final class DefaultOptionApp: TerminalApp {
    var body: some View {
        Text("既定")
    }
}
