import XCTest
import Foundation
import CTUITestSupport
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// クラッシュ時の復元が、どの `Terminal` が仕掛けたかに従うことを確かめる。
final class CrashRestoreOwnershipTests: XCTestCase {

    /// 先に仕掛けた端末を解放しても、後から仕掛けた端末の復元は働く。
    func testReleasingOneTerminalKeepsTheOtherArmed() throws {
        let released = try openPseudoTerminal()
        defer { released.close() }
        let kept = try openPseudoTerminal()
        defer { kept.close() }

        var releasedTerminal: Terminal? = Terminal(input: released.slave, output: released.slave)
        try releasedTerminal?.enableRawMode()

        let keptTerminal = Terminal(input: kept.slave, output: kept.slave)
        try keptTerminal.enableRawMode()
        defer { keptTerminal.restore() }

        releasedTerminal = nil

        XCTAssertFalse(isCanonicalMode(kept.slave), "raw モードになっていない")

        // クラッシュのシグナルを送るとテストプロセスごと落ちるため、
        // ハンドラが呼ぶ処理だけを直接確かめる。
        CrashRestorer.restoreTerminal()

        XCTAssertTrue(isCanonicalMode(kept.slave), "解放した端末に巻き込まれて端末属性が戻らない")
        XCTAssertTrue(
            readOutput(from: kept.master).contains(CrashRestorer.restoreSequence),
            "解放した端末に巻き込まれて復元用の制御コードが書き出されない"
        )
    }

    /// 先に仕掛けた端末を戻しても、後から仕掛けた端末の復元は働く。
    func testRestoringOneTerminalKeepsTheOtherArmed() throws {
        let restored = try openPseudoTerminal()
        defer { restored.close() }
        let kept = try openPseudoTerminal()
        defer { kept.close() }

        let restoredTerminal = Terminal(input: restored.slave, output: restored.slave)
        try restoredTerminal.enableRawMode()

        let keptTerminal = Terminal(input: kept.slave, output: kept.slave)
        try keptTerminal.enableRawMode()
        defer { keptTerminal.restore() }

        restoredTerminal.restore()

        CrashRestorer.restoreTerminal()

        XCTAssertTrue(isCanonicalMode(kept.slave), "戻した端末に巻き込まれて端末属性が戻らない")
        XCTAssertTrue(
            readOutput(from: kept.master).contains(CrashRestorer.restoreSequence),
            "戻した端末に巻き込まれて復元用の制御コードが書き出されない"
        )
    }

    /// 戻さずに捨てた端末の記述子は、クラッシュ時の書き込み先として残らない。
    func testDroppedTerminalLeavesNoDescriptorArmed() throws {
        let pty = try openPseudoTerminal()
        defer { pty.close() }

        do {
            let terminal = Terminal(input: pty.slave, output: pty.slave)
            try terminal.enableRawMode()
        }
        _ = readOutput(from: pty.master)

        // ここで記述子を閉じてはいけない。閉じると、書き込み先として残っていても書き込みが
        // 失敗するだけになり、残っているかを見分けられない。
        leaveCanonicalMode(pty.slave)

        CrashRestorer.restoreTerminal()

        XCTAssertFalse(isCanonicalMode(pty.slave), "捨てた端末の記述子へ端末属性を書き戻している")
        XCTAssertEqual(
            readOutput(from: pty.master, timeout: 0.2),
            "",
            "捨てた端末の記述子へ制御コードを書き出している"
        )
    }
}

// MARK: - テストの道具

/// 疑似端末の master と slave の組。
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

// 構造体の中から `close(2)` は直接呼べない。メンバーの `close()` が先に見つかる。
/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}

/// canonical モードかどうか。raw モードなら `false`。
///
/// - Parameters:
///   - descriptor: 調べるファイル記述子。
/// - Returns: canonical モードなら `true`。
private func isCanonicalMode(_ descriptor: Int32) -> Bool {
    var attributes = termios()
    guard tcgetattr(descriptor, &attributes) == 0 else { return false }
    return attributes.c_lflag & tcflag_t(ICANON) != 0
}

/// canonical モードを解く。
///
/// - Parameters:
///   - descriptor: 設定するファイル記述子。
private func leaveCanonicalMode(_ descriptor: Int32) {
    var attributes = termios()
    guard tcgetattr(descriptor, &attributes) == 0 else { return }
    attributes.c_lflag &= ~tcflag_t(ICANON)
    _ = tcsetattr(descriptor, TCSAFLUSH, &attributes)
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
