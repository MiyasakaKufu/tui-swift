/// 別スレッドや `Task` から、`Component.Message` の値をイベントループへ届ける送り口。
///
/// どのスレッド・どの `Task` からでも送れる。送られた値は、送った順に `Component.receive(_:)` へ渡され、
/// 続けて画面が描き直される。`ApplicationOptions.frameInterval` を設定していなくても届く。
///
/// - Note: ループが処理するより速く送ると、溜まった値をすべて `receive(_:)` へ渡してから、
///   まとめて 1 回だけ描き直す。値 1 つごとには描き直さない。
public struct MessageSender<Message: Sendable>: Sendable {

    private let mailbox: LoopMailbox<Message>

    /// 値を入れる先を指定して送り口を作る。
    ///
    /// - Parameters:
    ///   - mailbox: 送られた値を入れる先。
    init(mailbox: LoopMailbox<Message>) {
        self.mailbox = mailbox
    }

    /// 値をイベントループへ送る。
    ///
    /// - Parameters:
    ///   - message: 送る値。
    /// - Returns: 送ったなら `true`。ループが終わっているなら `false`。
    @discardableResult
    public func send(_ message: Message) -> Bool {
        mailbox.post(.message(message))
    }
}
