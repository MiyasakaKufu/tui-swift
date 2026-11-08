import XCTest
@testable import TUIKit

/// `LoopEventQueue` が `LoopEvent` をどう溜め、どう取り出すかを確かめる。
final class LoopEventQueueTests: XCTestCase {

    /// 取り出される前に何度入れても、`.wake` は 1 つしか溜まらない。
    func testWakesPostedBeforeTakeAreCoalesced() {
        let eventQueue = LoopEventQueue()
        for _ in 0..<1_000 { eventQueue.post(.wake) }

        XCTAssertEqual(labels(of: eventQueue.take()), ["wake"])
        XCTAssertEqual(labels(of: eventQueue.take()), [])
    }

    /// 取り出される前に何度入れても、`.idle` は 1 つしか溜まらない。
    func testIdlesPostedBeforeTakeAreCoalesced() {
        let eventQueue = LoopEventQueue()
        for _ in 0..<1_000 { eventQueue.post(.idle) }

        XCTAssertEqual(labels(of: eventQueue.take()), ["idle"])
    }

    /// `.wake` を挟んでも、`.invalidated` はすべて入れた順に取り出される。
    func testInvalidationsKeepOrderAcrossWakes() {
        let eventQueue = LoopEventQueue()
        for generation in 0..<100 {
            eventQueue.post(.invalidated(generation))
            eventQueue.post(.wake)
        }

        let events = eventQueue.take()
        let generations = events.compactMap { event -> Int? in
            if case .invalidated(let generation) = event { return generation }
            return nil
        }
        XCTAssertEqual(generations, Array(0..<100))
        XCTAssertEqual(labels(of: events).filter { $0 == "wake" }.count, 1)
    }

    /// 取り出した後に入れた `.wake` は、次に取り出すときにまた 1 つ渡る。
    func testWakeAfterTakeIsDeliveredAgain() {
        let eventQueue = LoopEventQueue()
        eventQueue.post(.wake)
        _ = eventQueue.take()
        eventQueue.post(.wake)

        XCTAssertEqual(labels(of: eventQueue.take()), ["wake"])
    }

    /// 閉じた後は受け付けず、知らせの `AsyncStream` も終わる。
    func testClosedQueueRejectsEventsAndFinishesArrivals() async {
        let eventQueue = LoopEventQueue()
        XCTAssertTrue(eventQueue.post(.invalidated(1)))
        eventQueue.close()

        XCTAssertFalse(eventQueue.post(.invalidated(2)))
        var arrivals = 0
        for await _ in eventQueue.arrivals { arrivals += 1 }
        XCTAssertEqual(arrivals, 1)
    }

    // MARK: - 補助

    /// 取り出した `LoopEvent` を、`case` の名前に直す。
    ///
    /// - Parameters:
    ///   - events: 名前に直す `LoopEvent`。
    /// - Returns: `case` の名前を、並びを保って並べたもの。
    private func labels(of events: [LoopEvent]) -> [String] {
        events.map { event in
            switch event {
            case .inputs: return "inputs"
            case .invalidated: return "invalidated"
            case .wake: return "wake"
            case .idle: return "idle"
            }
        }
    }
}
