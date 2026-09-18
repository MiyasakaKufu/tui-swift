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
    static var options: ApplicationOptions { ApplicationOptions(tracksMouse: true) }

    var body: some View {
        VStack(spacing: 1) {
            Text("上")
            Text("下")
        }
    }
}

final class ComponentTests: XCTestCase {

    func testDefaultHandleIgnoresEvents() {
        let component = DisplayOnlyComponent()
        XCTAssertEqual(component.handle(.key(KeyEvent(.up))), .ignored)
        XCTAssertEqual(component.handle(.resize(Size(width: 10, height: 4))), .ignored)
    }

    func testDefaultCursorPositionIsNil() {
        XCTAssertNil(DisplayOnlyComponent().cursorPosition)
    }

    func testBodyRendersThroughStaticType() {
        var buffer = Buffer(size: Size(width: 10, height: 1))
        DisplayOnlyComponent().body.render(into: &buffer, rect: buffer.bounds)
        XCTAssertEqual(buffer.text(ofRow: 0), "こんにちは")
    }

    func testDefaultOptions() {
        let options = ApplicationOptions.default
        XCTAssertTrue(options.usesAlternateScreen)
        XCTAssertFalse(options.tracksMouse)
        XCTAssertTrue(options.usesBracketedPaste)
        XCTAssertNil(options.frameInterval)
        XCTAssertTrue(options.quitsOnControlC)
    }

    func testQuitsOnUnhandledControlC() {
        let options = ApplicationOptions.default
        XCTAssertTrue(options.quits(onUnhandled: .key(KeyEvent(.character("c"), modifiers: .control))))
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("c")))))
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("q"), modifiers: .control))))
        XCTAssertFalse(options.quits(onUnhandled: .resize(Size(width: 1, height: 1))))
    }

    func testQuitsOnControlCCanBeDisabled() {
        let options = ApplicationOptions(quitsOnControlC: false)
        XCTAssertFalse(options.quits(onUnhandled: .key(KeyEvent(.character("c"), modifiers: .control))))
    }

    func testTerminalAppProvidesDefaultOptions() {
        XCTAssertTrue(MinimalApp.options.tracksMouse)
        XCTAssertTrue(DefaultOptionApp.options.quitsOnControlC)
        XCTAssertFalse(DefaultOptionApp.options.tracksMouse)
    }
}

/// `options` を書かないアプリ。既定値が使われる。
private final class DefaultOptionApp: TerminalApp {
    var body: some View {
        Text("既定")
    }
}
