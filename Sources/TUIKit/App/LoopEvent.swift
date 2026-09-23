/// イベントループが 1 つの `AsyncStream` から受け取るもの。
///
/// `InputEvent` と外部から送られたイベントを同じ `AsyncStream` へ流すため、
/// 取り出す順序は `yield` した順になる。
enum LoopEvent<Message: Sendable>: Sendable {
    /// tty から読んだバイト列を組み立てたもの。
    case input(InputEvent)
    /// 外部から送られたイベント。
    case message(Message)
    /// `poll(2)` の待ちが解けたことだけを伝える合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直す機会を、イベントが無くても作る。
    case wake
}
