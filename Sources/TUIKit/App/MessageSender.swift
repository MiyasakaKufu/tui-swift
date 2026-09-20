/// 外部で起きたことをイベントループへ届ける送り口。
///
/// どのスレッド・どの `Task` からでも送れる。送られたイベントは `Component.receive(_:)` へ渡され、
/// 続けて画面が描き直される。`ApplicationOptions.frameInterval` を設定していなくても届く。
///
/// - Note: アプリが自分で作業を起こすなら `Component.startupEffect` と `Effect` を使う。これを
///   直接使うのは、`Application` を自分で組み立てていて、ランタイムの知らない入力源
///   （自前のスレッド、C のコールバック）から届けるときだけ。`Application.sender` で受け取る。
public struct MessageSender<Message: Sendable>: Sendable {

    private let queue: EventQueue<Message>

    /// イベントを積むキューを指定して送り口を作る。
    ///
    /// - Parameters:
    ///   - queue: 送られたイベントを積むキュー。
    init(queue: EventQueue<Message>) {
        self.queue = queue
    }

    /// イベントをイベントループへ送る。
    ///
    /// - Parameters:
    ///   - message: 送るイベント。
    /// - Returns: 送ったなら `true`。積んでおける数の上限に達していて捨てたなら `false`。
    /// - Note: 上限は `ApplicationOptions.messageQueueLimit` で決める。
    ///   イベントループが終わった後に送ったイベントは、どこにも渡されない。
    @discardableResult
    public func send(_ message: Message) -> Bool {
        guard queue.send(message) else { return false }
        // 積む前に起こしてはいけない。起きた側が空のキューを見て寝直し、送ったイベントが
        // 次の入力かタイムアウトまで届かなくなる。
        SignalWatcher.wakeUp()
        return true
    }
}
