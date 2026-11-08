import Observation
import Synchronization

/// `Application.draw()` の 1 回で読んだ状態が、その後に変わったら、`LoopEventQueue` へ `.invalidated` を入れる型。
///
/// 状態とは、`Observation` に変化を知らせるプロパティ。`@State` を付けたプロパティの記憶域（`StateStorage`）、``ListState``、``TextFieldState``、`@Observable` を付けた型のプロパティが当たる。
@MainActor
final class RedrawTrigger {
    /// `RedrawTrigger.track(generation:_:)` が見張っている `Application.draw()` が何回目か。
    private let current = DrawGeneration()
    /// 前の `RedrawTrigger.track(generation:_:)` の見張りを外すために書き換える値。
    private let token = TrackingToken()
    /// `.invalidated` を入れる先。
    private let eventQueue: LoopEventQueue

    /// `RedrawTrigger` を作る。
    ///
    /// - Parameters:
    ///   - eventQueue: `.invalidated` を入れる先。
    init(eventQueue: LoopEventQueue) {
        self.eventQueue = eventQueue
    }

    /// `body` を呼び出し、その中で読んだ状態が後で変わったら、`.invalidated(generation)` を入れる。
    ///
    /// - Parameters:
    ///   - generation: 見張る `Application.draw()` が何回目か。
    ///   - body: `Application.draw()` の 1 回分を描くクロージャ。
    /// - Returns: `body` の戻り値。
    /// - Postcondition: 前の呼び出しで見張っていた状態は、もう見張っていない。後で変わっても入れない。
    /// - Note: `body` の中での代入では入れない。
    func track<Result>(generation: Int, _ body: () -> Result) -> Result {
        current.value.store(generation, ordering: .sequentiallyConsistent)
        // 前の見張りを外さずに済ませてはいけない。見張りは状態が変わるまで残るので、再描画するたびに、変わらない状態の見張りが溜まり続ける。
        token.value += 1
        let current = self.current
        let eventQueue = self.eventQueue
        return withObservationTracking {
            _ = token.value
            return body()
        } onChange: {
            guard current.value.load(ordering: .sequentiallyConsistent) == generation else { return }
            eventQueue.post(.invalidated(generation))
        }
    }
}

/// どのスレッドからも読み書きできる、`Application.draw()` が何回目か。
private final class DrawGeneration: Sendable {
    /// `Application.draw()` が何回目か。
    let value = Atomic<Int>(0)
}

/// 書き換えると、それを読んだ見張りが外れる値を持つクラス。
@Observable
private final class TrackingToken {
    /// 書き換える値。
    var value = 0
}
