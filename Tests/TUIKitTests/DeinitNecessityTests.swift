// H14 の計測。`Terminal.deinit` が何を担っているかを見る。
//
// `enableRawMode()` した `Terminal` を `restore()` せずに捨てる経路は、リポジトリの中には
// 無い（`enableRawMode()` の 3 か所はいずれも `restore()` と対）。`Terminal` は public なので
// 利用者は作れる。その経路で `deinit` が無いと何が残るかを測る。

import XCTest
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import CTUITestSupport
@testable import TUIKit

final class DeinitNecessityTests: XCTestCase {

    /// `restore()` せずに捨てた後、端末属性が raw のまま残るか。
    func testDropsTerminalWithoutRestore() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try XCTSkipIf(ctui_test_open_pty(&master, &slave) != 0, "疑似端末を開けない環境のため飛ばす")
        defer { close(master); close(slave) }

        var before = termios()
        XCTAssertEqual(tcgetattr(slave, &before), 0)

        do {
            let terminal = Terminal(input: slave, output: slave)
            try terminal.enableRawMode()
            // restore() を呼ばずに捨てる。
        }

        var after = termios()
        XCTAssertEqual(tcgetattr(slave, &after), 0)

        let echoBefore = before.c_lflag & tcflag_t(ECHO)
        let echoAfter = after.c_lflag & tcflag_t(ECHO)
        print("H14: ECHO 前=\(echoBefore) 後=\(echoAfter) 戻ったか=\(echoBefore == echoAfter)")

        let canonBefore = before.c_lflag & tcflag_t(ICANON)
        let canonAfter = after.c_lflag & tcflag_t(ICANON)
        print("H14: ICANON 前=\(canonBefore) 後=\(canonAfter) 戻ったか=\(canonBefore == canonAfter)")
    }

    /// `restore()` を呼んでから捨てた場合との比較。
    func testDropsTerminalAfterRestore() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        try XCTSkipIf(ctui_test_open_pty(&master, &slave) != 0, "疑似端末を開けない環境のため飛ばす")
        defer { close(master); close(slave) }

        var before = termios()
        XCTAssertEqual(tcgetattr(slave, &before), 0)

        do {
            let terminal = Terminal(input: slave, output: slave)
            try terminal.enableRawMode()
            terminal.restore()
        }

        var after = termios()
        XCTAssertEqual(tcgetattr(slave, &after), 0)
        print("H14: restore() あり ECHO 戻ったか=\(before.c_lflag & tcflag_t(ECHO) == after.c_lflag & tcflag_t(ECHO))")
    }
}
