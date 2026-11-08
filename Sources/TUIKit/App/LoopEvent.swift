/// イベントループが `LoopEventQueue` から受け取るもの。
///
/// 端末デバイスから読んだ `InputEvent` と、状態が変わったことを伝える合図を同じ `LoopEventQueue` へ入れるため、
/// 取り出す順序は入れた順になる。
enum LoopEvent: Sendable {
    /// 端末デバイスから読んだバイト列を組み立てたもの。``InputReader/wait(timeout:)`` 1 回分をまとめて運ぶ。
    case inputs([InputEvent])
    /// `Application.draw()` の 1 回で読んだ状態が、その後に変わったことを伝える合図。値は、その `Application.draw()` が何回目だったか。
    ///
    /// その `Application.draw()` の後にまだ再描画していなければ再描画する。再描画した後なら、`.idle` と同じに扱う。
    case invalidated(Int)
    /// `InputEvent` も状態の変化も無しに、ループを一巡させる合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直し、再描画する。
    case wake
    /// 自己パイプが無いときに、`poll(2)` の待ちを一定の間隔で切り上げたことを伝える合図。
    ///
    /// シグナルのフラグとウィンドウサイズを読み直す。どちらも変わっていなければ、再描画せずに次を待つ。
    case idle
}
