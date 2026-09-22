// H13 の計測。`deinit` の中から `self` に触ると何が起きるかを見る。
// 仮説は「参照数が増えるので解放の途中で不安定になる」。正しければ deinit が複数回走るか、
// 解放済みの領域へ触ることになる。
//
// 2 つの場合を別々の実行に分ける。同じ実行に入れると、後ろの場合が落ちたときに前の場合の
// 出力ごと失われる。

import Foundation

// 落ちたときに出力が消えないよう、行ごとに流す。
setvbuf(stdout, nil, _IONBF, 0)

/// `deinit` の中から自分のメソッドを呼ぶ。`Terminal.deinit { restore() }` と同じ形。
final class TouchesSelfInDeinit {
    static var deinitEntries = 0
    static var methodCalls = 0

    var value = 0

    func touch() {
        value += 1
        TouchesSelfInDeinit.methodCalls += 1
    }

    deinit {
        TouchesSelfInDeinit.deinitEntries += 1
        touch()
    }
}

/// `deinit` の中から `self` を外へ出す。参照数を増やして生き延びられるかを見る。
final class EscapesSelfInDeinit {
    static var escaped: UnsafeMutableRawPointer?
    static var deinitEntries = 0

    var value = 12345

    deinit {
        EscapesSelfInDeinit.deinitEntries += 1
        EscapesSelfInDeinit.escaped = Unmanaged.passUnretained(self).toOpaque()
    }
}

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "touch"

switch mode {
case "touch":
    let count = 10_000
    for _ in 0..<count {
        _ = TouchesSelfInDeinit()
    }
    print("H13: deinit から自分のメソッドを呼ぶ")
    print("H13:   作った数: \(count)")
    print("H13:   deinit に入った数: \(TouchesSelfInDeinit.deinitEntries)")
    print("H13:   メソッドが走った数: \(TouchesSelfInDeinit.methodCalls)")
    print("H13:   deinit が複数回走ったか: \(TouchesSelfInDeinit.deinitEntries != count)")
    print("H13:   最後まで到達した")

case "escape":
    do {
        _ = EscapesSelfInDeinit()
    }
    print("H13: deinit から self を外へ出す")
    print("H13:   deinit に入った数: \(EscapesSelfInDeinit.deinitEntries)")
    guard let pointer = EscapesSelfInDeinit.escaped else {
        print("H13:   外へ出せなかった")
        break
    }
    // 解放済みなら、ここは未定義。
    let revived = Unmanaged<EscapesSelfInDeinit>.fromOpaque(pointer).takeUnretainedValue()
    print("H13:   deinit の後に読んだ値: \(revived.value)")
    print("H13:   最後まで到達した")

default:
    print("H13: 知らない指定: \(mode)")
}
