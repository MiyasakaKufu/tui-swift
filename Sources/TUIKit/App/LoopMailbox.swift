import Foundation

/// イベントループへ届いた `LoopEvent` を溜めておき、ループが次に一巡するときにまとめて渡す箱。
///
/// どのスレッド・どの `Task` からでも入れられる。
///
/// - Invariant: 溜まっている `.wake` と `.idle` は、それぞれ多くとも 1 つ。
///   `.inputs` と `.message` は、入れた順にすべて残る。
final class LoopMailbox<Message: Sendable>: @unchecked Sendable {

    /// 何かが入ったことをループへ知らせる `AsyncStream`。要素そのものは運ばない。
    let arrivals: AsyncStream<Void>

    private let arrivalContinuation: AsyncStream<Void>.Continuation
    private let lock = NSLock()
    // `.inputs` と `.message` の数に上限を付けてはいけない。溢れた分を捨てることになり、
    // `MessageSender` で送られた値で埋まると、後から届いたキーが捨てられて終われなくなる。
    private var pending: [LoopEvent<Message>] = []
    private var hasPendingWake = false
    private var hasPendingIdle = false
    private var isClosed = false

    /// 空の箱を作る。
    init() {
        // 知らせの上限を外してはいけない。ループより速く入れられると、中身の無い知らせが
        // 溜まり続けてメモリが増え、ループは空の `take()` を溜まった数だけ繰り返す。
        let (arrivals, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        self.arrivals = arrivals
        self.arrivalContinuation = continuation
    }

    /// `LoopEvent` を入れ、ループへ知らせる。
    ///
    /// - Parameters:
    ///   - event: 入れる `LoopEvent`。`.wake` と `.idle` は、同じものが既に溜まっていれば入れない。
    /// - Returns: 受け付けたなら `true`。`close()` の後なら `false`。
    @discardableResult
    func post(_ event: LoopEvent<Message>) -> Bool {
        lock.lock()
        guard !isClosed else {
            lock.unlock()
            return false
        }
        switch event {
        case .wake:
            if !hasPendingWake { pending.append(event) }
            hasPendingWake = true
        case .idle:
            if !hasPendingIdle { pending.append(event) }
            hasPendingIdle = true
        case .inputs, .message:
            pending.append(event)
        }
        lock.unlock()

        // 溜める前に知らせてはいけない。ループが知らせを受けて `take()` した後に溜まると、
        // 次の知らせが来るまで取り出されない。
        arrivalContinuation.yield()
        return true
    }

    /// 溜まっている `LoopEvent` を、入れた順にすべて取り出す。
    ///
    /// - Returns: 取り出した `LoopEvent`。何も溜まっていなければ空。
    func take() -> [LoopEvent<Message>] {
        lock.lock()
        defer { lock.unlock() }
        let events = pending
        pending = []
        hasPendingWake = false
        hasPendingIdle = false
        return events
    }

    /// 以後の `post(_:)` を断り、`arrivals` を終える。
    func close() {
        lock.lock()
        isClosed = true
        lock.unlock()
        arrivalContinuation.finish()
    }
}
