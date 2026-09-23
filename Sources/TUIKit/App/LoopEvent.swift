/// イベントループが 1 つの `AsyncStream` から受け取るもの。
///
/// `InputEvent` と外部から送られたイベントを同じ `AsyncStream` へ流すため、
/// 取り出す順序は `yield` した順になる。
enum LoopEvent<Message: Sendable>: Sendable {
    /// tty から読んだバイト列を組み立てたもの。`InputReader.wait(timeout:)` 1 回分をまとめて運ぶ。
    case inputs([InputEvent])
    /// 外部から送られたイベント。
    case message(Message)
    /// `InputEvent` を伴わずに `poll(2)` の待ちが解けたことを伝える合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直す機会を、イベントが無くても作る。
    case wake
}
