// H14 の計測。`Terminal.deinit` が何を担っているかを見る。
//
// `enableRawMode()` した `Terminal` を `restore()` せずに捨てる経路は、リポジトリの中には
// 無い（`enableRawMode()` の 3 か所はいずれも `restore()` と対）。`Terminal` は public なので
// 利用者は作れる。その経路で `deinit` の有無によって端末属性の戻り方が変わるかを測る。
//
// テストではなく実行ファイルにしてある。テストに置くと、案 B では隔離の注釈が要り、
// main では要らないため、同じコードを両方で走らせられない。

import Foundation
import CTUITestSupport
import TUIKit

setvbuf(stdout, nil, _IONBF, 0)

var master: Int32 = -1
var slave: Int32 = -1
guard ctui_test_open_pty(&master, &slave) == 0 else {
    print("H14: 疑似端末を開けない")
    exit(2)
}
defer { close(master); close(slave) }

var before = termios()
guard tcgetattr(slave, &before) == 0 else {
    print("H14: 属性を読めない")
    exit(2)
}

let dropsWithoutRestore = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "drop"

do {
    let terminal = Terminal(input: slave, output: slave)
    try terminal.enableRawMode()
    if !dropsWithoutRestore { terminal.restore() }
}

var after = termios()
guard tcgetattr(slave, &after) == 0 else {
    print("H14: 属性を読み直せない")
    exit(2)
}

let mode = dropsWithoutRestore ? "restore() せずに捨てる" : "restore() してから捨てる"
print("H14: \(mode)")
for (name, flag) in [("ECHO", ECHO), ("ICANON", ICANON), ("ISIG", ISIG)] {
    let a = before.c_lflag & tcflag_t(flag)
    let b = after.c_lflag & tcflag_t(flag)
    print("H14:   \(name) 戻ったか: \(a == b)（前=\(a) 後=\(b)）")
}
