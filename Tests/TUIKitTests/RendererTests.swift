import XCTest
@testable import TUIKit

@MainActor
final class RendererTests: XCTestCase {

    func testFirstRenderClearsScreen() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("abc", at: .zero)

        renderer.render(buffer)

        XCTAssertTrue(output.contents.contains(ANSI.clearScreen))
        XCTAssertTrue(output.contents.contains("abc"))
        XCTAssertEqual(output.flushCount, 1)
    }

    func testSecondRenderOnlyEmitsChangedCells() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 5, height: 1))
        buffer.write("abcde", at: .zero)
        renderer.render(buffer)

        output.reset()
        buffer[2, 0] = Cell(character: "X")
        renderer.render(buffer)

        XCTAssertFalse(output.contents.contains(ANSI.clearScreen))
        XCTAssertTrue(output.contents.contains(ANSI.moveCursor(row: 1, column: 3)))
        XCTAssertTrue(output.contents.contains("X"))
        XCTAssertFalse(output.contents.contains("abc"))
    }

    func testUnchangedBufferEmitsNoCellOutput() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("abcd", at: .zero)
        renderer.render(buffer)

        output.reset()
        renderer.render(buffer)

        XCTAssertFalse(output.contents.contains("abcd"))
        XCTAssertFalse(output.contents.contains(ANSI.moveCursor(row: 1, column: 1)))
    }

    func testInvalidateForcesFullRedraw() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("abcd", at: .zero)
        renderer.render(buffer)

        output.reset()
        renderer.invalidate()
        renderer.render(buffer)

        XCTAssertTrue(output.contents.contains(ANSI.clearScreen))
        XCTAssertTrue(output.contents.contains("abcd"))
    }

    func testSizeChangeForcesFullRedraw() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 2, height: 1))
        renderer.render(buffer)

        output.reset()
        buffer.resize(to: Size(width: 3, height: 1))
        renderer.render(buffer)

        XCTAssertTrue(output.contents.contains(ANSI.clearScreen))
    }

    func testCursorIsShownWhenPositionGiven() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        let buffer = Buffer(size: Size(width: 3, height: 1))

        renderer.render(buffer, cursor: Point(x: 1, y: 0))

        XCTAssertTrue(
            output.contents.hasSuffix(
                ANSI.moveCursor(row: 1, column: 2) + ANSI.showCursor + ANSI.endSynchronizedUpdate
            )
        )
    }

    func testCursorStaysHiddenWithoutPosition() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        let buffer = Buffer(size: Size(width: 3, height: 1))

        renderer.render(buffer)

        XCTAssertTrue(output.contents.hasPrefix(ANSI.beginSynchronizedUpdate + ANSI.hideCursor))
        XCTAssertFalse(output.contents.contains(ANSI.showCursor))
    }

    func testFrameIsWrappedInSynchronizedUpdate() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("abc", at: .zero)

        renderer.render(buffer)

        XCTAssertTrue(output.contents.hasPrefix(ANSI.beginSynchronizedUpdate))
        XCTAssertTrue(output.contents.hasSuffix(ANSI.endSynchronizedUpdate))
    }

    func testDifferentialFrameIsWrappedInSynchronizedUpdate() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("abc", at: .zero)
        renderer.render(buffer)

        output.reset()
        buffer[1, 0] = Cell(character: "X")
        renderer.render(buffer)

        XCTAssertTrue(output.contents.hasPrefix(ANSI.beginSynchronizedUpdate))
        XCTAssertTrue(output.contents.hasSuffix(ANSI.endSynchronizedUpdate))
    }

    func testSynchronizedUpdateIsWrittenAsOneFlush() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 3, height: 1))
        buffer.write("abc", at: .zero)

        renderer.render(buffer)

        XCTAssertEqual(output.writeCount, 1)
        XCTAssertEqual(output.flushCount, 1)
    }

    func testStyleChangeEmitsSGR() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 2, height: 1))
        buffer.write("a", at: .zero, style: Style(foreground: .red))
        renderer.render(buffer)

        XCTAssertTrue(output.contents.contains("\u{1B}[31m"))
    }

    func testWideCharacterIsNotSplitAcrossUpdates() async {
        let output = StringOutput()
        let renderer = Renderer(output: output)
        var buffer = Buffer(size: Size(width: 4, height: 1))
        buffer.write("ab", at: .zero)
        renderer.render(buffer)

        output.reset()
        var next = Buffer(size: Size(width: 4, height: 1))
        next.write("あ", at: .zero)
        renderer.render(next)

        XCTAssertTrue(output.contents.contains("あ"))
        XCTAssertTrue(output.contents.contains(ANSI.moveCursor(row: 1, column: 1)))
    }
}
