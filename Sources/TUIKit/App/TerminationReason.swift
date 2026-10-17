/// ``Application`` がイベントループを抜けた理由を表す型。
///
/// ``TerminalApp/didTerminate(_:)`` が受け取る。
public enum TerminationReason: Hashable, Sendable {
    /// ``TerminalApp/isFinished`` が `true` になった。
    case finished
    /// ``TerminalApp/handle(_:)`` が `.ignored` を返した Ctrl+C を受け取った（``ApplicationOptions/quitsOnControlC``）。
    case controlC
    /// 終了シグナル（SIGTERM・SIGHUP・SIGINT・SIGQUIT）が届いた。値はシグナルの番号。
    case signal(Int32)
    /// ``Application/stop()`` が呼び出された。
    case stopped
    /// 一時停止から再開したときに、端末デバイスを raw モードへ戻せなかった（``Terminal/reactivate()`` がエラーを投げた）。
    case resumeFailed
    /// ``Application/run()`` を呼び出している `Task` が打ち切られた。
    case cancelled
}
