/// 外部で起きたことをイベントループへ届ける送り口。
///
/// どのスレッド・どの `Task` からでも送れる。送られたイベントは `Component.receive(_:)` へ渡され、
/// 続けて画面が描き直される。`ApplicationOptions.frameInterval` を設定していなくても届く。
public struct MessageSender<Message: Sendable>: Sendable {

    private let continuation: AsyncStream<LoopEvent<Message>>.Continuation

    /// イベントを流す先を指定して送り口を作る。
    ///
    /// - Parameters:
    ///   - continuation: 送られたイベントを流す先。
    init(continuation: AsyncStream<LoopEvent<Message>>.Continuation) {
        self.continuation = continuation
    }

    /// イベントをイベントループへ送る。
    ///
    /// - Parameters:
    ///   - message: 送るイベント。
    /// - Returns: 送ったなら `true`。積んでおける数の上限に達していて捨てたか、ループが
    ///   終わっているなら `false`。
    /// - Note: 上限は `ApplicationOptions.messageQueueLimit` で決める。
    @discardableResult
    public func send(_ message: Message) -> Bool {
        if case .enqueued = continuation.yield(.message(message)) { return true }
        return false
    }
}
