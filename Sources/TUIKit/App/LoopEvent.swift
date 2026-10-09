/// イベントループが `LoopEventQueue` から受け取るもの。
///
/// `InputEvent` と、`MessageSender` で送られた値を同じ `LoopEventQueue` へ入れるため、
/// 取り出す順序は入れた順になる。
enum LoopEvent<Message: Sendable>: Sendable {
    /// 端末デバイスから読んだバイト列を組み立てたもの。`InputReader.wait(timeout:)` 1 回分をまとめて運ぶ。
    case inputs([InputEvent])
    /// `MessageSender.send(_:)` で送られた値。
    case message(Message)
    /// `InputEvent` も送られた値も無しに、ループを一巡させる合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直し、`Component.update(elapsed:)` を呼び出して描き直す。
    case wake
    /// 自己パイプが無いときに、`poll(2)` の待ちを一定の間隔で切り上げたことを伝える合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直す。どちらも変わっていなければ、
    /// `Component.update(elapsed:)` を呼び出さず、描き直さずに次を待つ。
    case idle
}
