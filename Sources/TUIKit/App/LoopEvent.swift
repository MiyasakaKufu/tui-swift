/// イベントループが 1 つの `AsyncStream` から受け取るもの。
///
/// `InputEvent` と、`MessageSender` で送られた値を同じ `AsyncStream` へ流すため、
/// 取り出す順序は `yield` した順になる。
enum LoopEvent<Message: Sendable>: Sendable {
    /// tty から読んだバイト列を組み立てたもの。`InputReader.wait(timeout:)` 1 回分をまとめて運ぶ。
    case inputs([InputEvent])
    /// `MessageSender.send(_:)` で送られた値。
    case message(Message)
    /// `InputEvent` も送られた値も無しに、ループを一巡させる合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直し、`update(elapsed:)` を呼んで描き直す。
    case wake
    /// 自己パイプが無いときに、`poll(2)` の待ちを一定の間隔で切り上げたことを伝える合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直す。どちらも変わっていなければ、
    /// `update(elapsed:)` を呼ばず、描き直さずに次を待つ。
    case idle
}
