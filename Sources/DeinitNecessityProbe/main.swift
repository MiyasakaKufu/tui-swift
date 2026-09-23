// `Terminal` を `restore()` せずに捨てたとき、何がどこへ戻るかを測る。使い捨て。
//
// 戻す先は 2 つあり、持ち主が違う。
//
// - termios — tty が持つ。`tcsetattr` で書き換える。プロセスが終わっても残る
// - 設定を打ち消す列 — 端末エミュレータが持つ状態を戻させる。記述子への `write(2)`
//
// 前の計測（H14・H17）は termios だけを見ていた。ここは列の側を見る。

import Foundation
import CTUITestSupport
import TUIKit

setvbuf(stdout, nil, _IONBF, 0)

/// 打ち消す列のうち、エミュレータが持つ状態に効くもの。
let expectedSequences: [(name: String, bytes: String)] = [
    ("代替画面から出る", "\u{1B}[?1049l"),
    ("カーソルを表示する", "\u{1B}[?25h"),
    ("マウスの通知を止める", "\u{1B}[?1000l"),
    ("スタイルを戻す", "\u{1B}[0m"),
]

var master: Int32 = -1
var slave: Int32 = -1
guard ctui_test_open_pty(&master, &slave) == 0 else {
    print("PROBE: 疑似端末を開けない")
    exit(2)
}

var before = termios()
guard tcgetattr(slave, &before) == 0 else {
    print("PROBE: termios を読めない")
    exit(2)
}

// 親が master 側を読み続ける。読まないと出力バッファが詰まり、子の write(2) が返らない。
let capturedLock = NSLock()
nonisolated(unsafe) var captured = Data()
let drain = Thread {
    var buffer = [UInt8](repeating: 0, count: 4096)
    while true {
        let count = read(master, &buffer, buffer.count)
        if count <= 0 { break }
        capturedLock.lock()
        captured.append(contentsOf: buffer[0..<count])
        capturedLock.unlock()
    }
}
drain.start()

let child = fork()
if child == 0 {
    do {
        let terminal = Terminal(input: slave, output: slave)
        try terminal.enableRawMode()
        // エミュレータ側に状態を作る。作らないと、戻ったかどうかを見分けられない。
        terminal.enterAlternateScreen()
        terminal.setMouseTracking(.click)
        terminal.flush()
        _ = terminal
    } catch {
        _exit(3)
    }
    exit(0)
}
guard child > 0 else {
    print("PROBE: fork できない")
    exit(2)
}
var status: Int32 = 0
waitpid(child, &status, 0)

Thread.sleep(forTimeInterval: 0.3)

var after = termios()
guard tcgetattr(slave, &after) == 0 else { exit(2) }

capturedLock.lock()
let text = String(decoding: captured, as: UTF8.self)
let length = captured.count
capturedLock.unlock()

print("PROBE: 子の終了値 \(status)")
print("PROBE: [termios]")
for (name, flag) in [("ECHO", ECHO), ("ICANON", ICANON), ("ISIG", ISIG)] {
    print("PROBE:   \(name) 戻ったか: \(before.c_lflag & tcflag_t(flag) == after.c_lflag & tcflag_t(flag))")
}
print("PROBE: [エミュレータ宛の列] 読んだ長さ \(length) バイト")
for expected in expectedSequences {
    print("PROBE:   \(expected.name): \(text.contains(expected.bytes))")
}
