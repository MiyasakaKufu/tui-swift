import Synchronization

/// イベントループへ届いた `LoopEvent` を溜めておき、ループが次に一巡するときにまとめて渡すキュー。
///
/// どのスレッド・どの `Task` からでも入れられる。
///
/// - Invariant: 溜まっている `.wake` と `.idle` は、それぞれ多くとも 1 つ。
///   `.inputs` と `.message` は、入れた順にすべて残る。
final class LoopEventQueue<Message: Sendable>: Sendable {

    /// `Mutex` で守る、溜まっている `LoopEvent` と閉じたかどうか。
    private struct State {
        // `.inputs` と `.message` の数に上限を付けてはいけない。溢れた分を捨てることになり、
        // `MessageSender` で送られた値で埋まると、後から届いたキーが捨てられて終われなくなる。
        var pending: [LoopEvent<Message>] = []
        var hasPendingWake = false
        var hasPendingIdle = false
        var isClosed = false
    }

    /// 何かが入ったことをループへ知らせる `AsyncStream`。要素そのものは運ばない。
    let arrivals: AsyncStream<Void>

    private let arrivalContinuation: AsyncStream<Void>.Continuation
    // `actor` にしたり `@MainActor` に隔離したりしてはいけない。入力スレッドと `MessageSender.send(_:)` は
    // 同期の文脈から入れるので `Task` を介して渡すことになり、`Task` 同士の実行順が保証されないため、
    // 入れた順が崩れる。
    private let state = Mutex(State())

    /// 空のキューを作る。
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
        let accepted: Bool = state.withLock { state in
            guard !state.isClosed else { return false }
            switch event {
            case .wake:
                if !state.hasPendingWake { state.pending.append(event) }
                state.hasPendingWake = true
            case .idle:
                if !state.hasPendingIdle { state.pending.append(event) }
                state.hasPendingIdle = true
            case .inputs, .message:
                state.pending.append(event)
            }
            return true
        }
        guard accepted else { return false }

        // 溜める前に知らせてはいけない。ループが知らせを受けて `take()` した後に溜まると、
        // 次の知らせが来るまで取り出されない。
        arrivalContinuation.yield()
        return true
    }

    /// 溜まっている `LoopEvent` を、入れた順にすべて取り出す。
    ///
    /// - Returns: 取り出した `LoopEvent`。何も溜まっていなければ空。
    func take() -> [LoopEvent<Message>] {
        state.withLock { state in
            let events = state.pending
            state.pending = []
            state.hasPendingWake = false
            state.hasPendingIdle = false
            return events
        }
    }

    /// 以後の `post(_:)` を断り、`arrivals` を終える。
    func close() {
        state.withLock { $0.isClosed = true }
        arrivalContinuation.finish()
    }
}
