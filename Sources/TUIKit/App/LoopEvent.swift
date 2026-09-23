/// イベントループが 1 本の列から受け取るもの。
///
/// 端末から届いた入力と外部から送られたイベントを同じ `AsyncStream` へ流すため、
/// 取り出す順序は `yield` した順になる。
enum LoopEvent<Message: Sendable>: Sendable {
    /// 端末から届いた入力。
    case input(InputEvent)
    /// 外部から送られたイベント。
    case message(Message)
    /// 入力待ちが解けたことだけを伝える合図。
    ///
    /// シグナルのフラグと端末サイズを読み直す機会を、イベントが無くても作る。
    case wake
}
