import XCTest
import Foundation
import CTUITestSupport
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ウィンドウタイトルとカーソル形状の設定と、その戻し方を確かめる。
@MainActor
final class TerminalAppearanceTests: XCTestCase {

    /// タイトルは `OSC 0` とベルで囲んで送る。
    func testWindowTitleSequenceWrapsTitleInOperatingSystemCommand() async {
        XCTAssertEqual(ANSI.setWindowTitle("タイトル"), "\u{1B}]0;タイトル\u{07}")
    }

    /// タイトルに混じった制御文字は落とす。
    func testWindowTitleSequenceDropsControlCharacters() async {
        XCTAssertEqual(
            ANSI.setWindowTitle("a\u{07}b\u{1B}c\u{7F}d\u{9C}e"),
            "\u{1B}]0;abcde\u{07}"
        )
    }

    /// カーソル形状は `DECSCUSR` の番号で送る。
    func testCursorShapeSequencesUseDECSCUSRParameters() async {
        XCTAssertEqual(ANSI.setCursorShape(.default), "\u{1B}[0 q")
        XCTAssertEqual(ANSI.setCursorShape(.blinkingBlock), "\u{1B}[1 q")
        XCTAssertEqual(ANSI.setCursorShape(.block), "\u{1B}[2 q")
        XCTAssertEqual(ANSI.setCursorShape(.blinkingUnderline), "\u{1B}[3 q")
        XCTAssertEqual(ANSI.setCursorShape(.underline), "\u{1B}[4 q")
        XCTAssertEqual(ANSI.setCursorShape(.blinkingBar), "\u{1B}[5 q")
        XCTAssertEqual(ANSI.setCursorShape(.bar), "\u{1B}[6 q")
    }

    /// クラッシュしたときも、カーソル形状とタイトルが戻る。
    func testCrashRestoreSequenceResetsCursorShapeAndWindowTitle() async {
        XCTAssertTrue(CrashRestorer.restoreSequence.contains(ANSI.setCursorShape(.default)))
        XCTAssertTrue(CrashRestorer.restoreSequence.contains(ANSI.restoreWindowTitle))
    }

    /// 設定すると、タイトルを積んでから送り、カーソル形状を送る。
    func testSettingTitleAndShapeSavesTitleFirst() async throws {
        let pty = try openPseudoTerminal()
        defer { pty.close() }

        let terminal = Terminal(input: pty.slave, output: pty.slave)
        defer { terminal.restore() }

        terminal.setWindowTitle("タイトル")
        terminal.setCursorShape(.bar)

        let output = readOutput(from: pty.master)
        XCTAssertEqual(
            output,
            ANSI.saveWindowTitle + ANSI.setWindowTitle("タイトル") + ANSI.setCursorShape(.bar)
        )
    }

    /// 一時停止では設定する前のタイトルと形へ戻し、再開では設定し直す。
    func testDeactivateRestoresTitleAndShapeAndReactivateAppliesThemAgain() async throws {
        let pty = try openPseudoTerminal()
        defer { pty.close() }

        // `Terminal.deactivate()` や `Terminal.restore()` を呼び出した後で master を読むように直してはいけない。
        // macOS ではそれらが戻らず、テストが止まる。
        // raw モードの間は書き出しが送られ切るのを待ってから端末デバイスの termios を戻し、macOS の疑似端末では master から読み出すまで送られ切らない。
        // Linux では待たずに済むので、Linux だけで確かめても気づけない。
        let drain = OutputDrain(descriptor: pty.master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let terminal = Terminal(input: pty.slave, output: pty.slave)
        try terminal.enableRawMode()
        defer { terminal.restore() }

        terminal.setWindowTitle("タイトル")
        terminal.setCursorShape(.bar)
        XCTAssertTrue(drain.waitForOutput(containing: ANSI.setCursorShape(.bar), timeout: 2))
        drain.reset()

        terminal.deactivate()

        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.setCursorShape(.default), timeout: 2),
            "一時停止でカーソル形状が戻らない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.restoreWindowTitle, timeout: 2),
            "一時停止でタイトルが戻らない"
        )
        XCTAssertTrue(drain.waitForOutput(containing: ANSI.showCursor, timeout: 2))
        drain.reset()

        try terminal.reactivate()

        XCTAssertTrue(
            drain.waitForOutput(
                containing: ANSI.saveWindowTitle + ANSI.setWindowTitle("タイトル"),
                timeout: 2
            ),
            "再開でタイトルが設定し直されない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.setCursorShape(.bar), timeout: 2),
            "再開でカーソル形状が設定し直されない"
        )
    }

    /// 設定していなければ、一時停止でどちらの復元も送らない。
    func testDeactivateSendsNoRestoreWhenNothingWasSet() async throws {
        let pty = try openPseudoTerminal()
        defer { pty.close() }

        let terminal = Terminal(input: pty.slave, output: pty.slave)
        defer { terminal.restore() }

        terminal.deactivate()

        let output = readOutput(from: pty.master)
        XCTAssertFalse(output.contains(ANSI.restoreWindowTitle), "積んでいないタイトルを戻している")
        XCTAssertFalse(output.contains(ANSI.setCursorShape(.default)), "変えていない形を戻している")
    }

    /// 終了すると、次に設定するときはタイトルを積み直す。
    func testRestoreForgetsTitleSoTheNextSetSavesAgain() async throws {
        let pty = try openPseudoTerminal()
        defer { pty.close() }

        let terminal = Terminal(input: pty.slave, output: pty.slave)

        terminal.setWindowTitle("タイトル")
        terminal.restore()
        _ = readOutput(from: pty.master)

        terminal.setWindowTitle("別のタイトル")

        let output = readOutput(from: pty.master)
        XCTAssertEqual(output, ANSI.saveWindowTitle + ANSI.setWindowTitle("別のタイトル"))
    }
}

// MARK: - テスト用の疑似端末

/// テスト用の疑似端末の両端。
///
/// - Warning: master を読まないまま大量に書き出してはいけない。
///   読まずに溜まったバイト列がカーネルの上限に達すると、slave への `write(2)` が戻らなくなる。
private struct PseudoTerminalPair {
    let master: Int32
    let slave: Int32

    /// 両端を閉じる。
    func close() {
        closeDescriptor(slave)
        closeDescriptor(master)
    }
}

/// 疑似端末を開く。
///
/// - Returns: 開いた疑似端末の両端。
/// - Throws: 疑似端末を開けない環境では `XCTSkip`。
private func openPseudoTerminal() throws -> PseudoTerminalPair {
    var master: Int32 = -1
    var slave: Int32 = -1
    try XCTSkipIf(ctui_test_open_pty(&master, &slave) != 0, "疑似端末を開けない環境のため飛ばす")
    return PseudoTerminalPair(master: master, slave: slave)
}

// 構造体の中から `close(2)` は直接呼び出せない。メンバーの `close()` が先に見つかる。
/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}

/// 疑似端末へ書き出されたものを読み出す。
///
/// - Parameters:
///   - descriptor: 読み出すファイル記述子。
///   - timeout: 読み出しに費やす秒数の上限。
/// - Returns: 読み出した内容。
private func readOutput(from descriptor: Int32, timeout: Double = 0.5) -> String {
    var collected: [UInt8] = []
    var scratch = [UInt8](repeating: 0, count: 4096)
    let deadline = Date().addingTimeInterval(timeout)

    while Date() < deadline {
        var polled = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
        guard poll(&polled, 1, 20) > 0 else {
            if !collected.isEmpty { break }
            continue
        }
        let count = scratch.withUnsafeMutableBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return read(descriptor, base, buffer.count)
        }
        if count <= 0 { break }
        collected.append(contentsOf: scratch[0..<count])
    }

    return String(decoding: collected, as: UTF8.self)
}
