// H14・H17 の計測。`Terminal.deinit` が担っている仕事と、その代替が効くかを見る。
//
// `enableRawMode()` した `Terminal` を `restore()` せずに捨てる経路は、リポジトリの中には
// 無い（`enableRawMode()` の 3 か所はいずれも `restore()` と対）。`Terminal` は public なので
// 利用者は作れる。
//
// テストではなく実行ファイルにしてある。テストに置くと、案 B では隔離の注釈が要り、
// main では要らないため、同じコードを両方で走らせられない。

import Foundation
import CTUITestSupport
import TUIKit

setvbuf(stdout, nil, _IONBF, 0)

/// 疑似端末を開き、属性を読む。
func openPTY() -> (master: Int32, slave: Int32, attributes: termios)? {
    var master: Int32 = -1
    var slave: Int32 = -1
    guard ctui_test_open_pty(&master, &slave) == 0 else { return nil }
    var attributes = termios()
    guard tcgetattr(slave, &attributes) == 0 else { return nil }
    return (master, slave, attributes)
}

/// 前後の属性を比べて出す。
func report(_ label: String, before: termios, after: termios) {
    print("H14: \(label)")
    for (name, flag) in [("ECHO", ECHO), ("ICANON", ICANON), ("ISIG", ISIG)] {
        let a = before.c_lflag & tcflag_t(flag)
        let b = after.c_lflag & tcflag_t(flag)
        print("H14:   \(name) 戻ったか: \(a == b)（前=\(a) 後=\(b)）")
    }
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "keep"

guard let pty = openPTY() else {
    print("H14: 疑似端末を開けない")
    exit(2)
}
let slave = pty.slave
let before = pty.attributes

switch mode {
case "keep", "drop":
    // 同じプロセスの中で、捨てた直後の状態を見る。deinit が走るのはここ。
    do {
        let terminal = Terminal(input: slave, output: slave)
        try terminal.enableRawMode()
        if mode == "keep" { terminal.restore() }
    }
    var after = termios()
    guard tcgetattr(slave, &after) == 0 else { exit(2) }
    report(mode == "keep" ? "restore() してから捨てる" : "restore() せずに捨てる",
           before: before, after: after)

case "exit":
    // 子プロセスで捨ててそのまま抜け、親から端末の状態を見る。deinit ではなく
    // プロセス終了時の後片付け（atexit など）が効くかはここで分かれる。
    let child = fork()
    if child == 0 {
        do {
            let terminal = Terminal(input: slave, output: slave)
            try terminal.enableRawMode()
            _ = terminal  // restore() を呼ばずに抜ける
        } catch {
            _exit(3)
        }
        exit(0)
    }
    guard child > 0 else {
        print("H14: fork できない")
        exit(2)
    }
    var status: Int32 = 0
    waitpid(child, &status, 0)
    var after = termios()
    guard tcgetattr(slave, &after) == 0 else { exit(2) }
    report("子プロセスが restore() せずに終了（子の終了値 \(status)）",
           before: before, after: after)

default:
    print("H14: 知らない指定: \(mode)")
}
