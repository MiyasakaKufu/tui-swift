// H13 の計測。`deinit` の中から `self` のメソッドを呼ぶと何が起きるかを見る。
// 仮説は「参照数が増えるので解放の途中で不安定になる」。正しければ deinit が複数回走るか、
// 解放済みの領域へ触ることになる。

import Foundation

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

let count = 10_000
for _ in 0..<count {
    _ = TouchesSelfInDeinit()
}
print("1. deinit から自分のメソッドを呼ぶ")
print("   作った数: \(count)")
print("   deinit に入った数: \(TouchesSelfInDeinit.deinitEntries)")
print("   メソッドが走った数: \(TouchesSelfInDeinit.methodCalls)")
print("   deinit が複数回走ったか: \(TouchesSelfInDeinit.deinitEntries != count)")

do {
    _ = EscapesSelfInDeinit()
}
print("2. deinit から self を外へ出す")
print("   deinit に入った数: \(EscapesSelfInDeinit.deinitEntries)")
if let pointer = EscapesSelfInDeinit.escaped {
    // 解放済みなら、ここは未定義。ASan を付けて走らせて何が出るかを見る。
    let revived = Unmanaged<EscapesSelfInDeinit>.fromOpaque(pointer).takeUnretainedValue()
    print("   deinit の後に読んだ値: \(revived.value)")
}
print("3. ここまで到達した")
