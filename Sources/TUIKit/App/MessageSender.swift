/// 別スレッドや `Task` から、`Component.Message` の値をイベントループへ届ける送り口。
///
/// どのスレッド・どの `Task` からでも送れる。送られた値は `Component.receive(_:)` へ渡され、
/// 続けて画面が描き直される。`ApplicationOptions.frameInterval` を設定していなくても届く。
public struct MessageSender<Message: Sendable>: Sendable {

    private let continuation: AsyncStream<LoopEvent<Message>>.Continuation

    /// 値を流す先を指定して送り口を作る。
    ///
    /// - Parameters:
    ///   - continuation: 送られた値を流す先。
    init(continuation: AsyncStream<LoopEvent<Message>>.Continuation) {
        self.continuation = continuation
    }

    /// 値をイベントループへ送る。
    ///
    /// - Parameters:
    ///   - message: 送る値。
    /// - Returns: 送ったなら `true`。ループが終わっているなら `false`。
    @discardableResult
    public func send(_ message: Message) -> Bool {
        if case .enqueued = continuation.yield(.message(message)) { return true }
        return false
    }
}
