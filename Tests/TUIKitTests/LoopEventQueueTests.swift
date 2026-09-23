import XCTest
@testable import TUIKit

/// `LoopEventQueue` が `LoopEvent` をどう溜め、どう取り出すかを確かめる。
final class LoopEventQueueTests: XCTestCase {

    /// 取り出される前に何度入れても、`.wake` は 1 つしか溜まらない。
    func testWakesPostedBeforeTakeAreCoalesced() {
        let eventQueue = LoopEventQueue<Int>()
        for _ in 0..<1_000 { eventQueue.post(.wake) }

        XCTAssertEqual(labels(of: eventQueue.take()), ["wake"])
        XCTAssertEqual(labels(of: eventQueue.take()), [])
    }

    /// 取り出される前に何度入れても、`.idle` は 1 つしか溜まらない。
    func testIdlesPostedBeforeTakeAreCoalesced() {
        let eventQueue = LoopEventQueue<Int>()
        for _ in 0..<1_000 { eventQueue.post(.idle) }

        XCTAssertEqual(labels(of: eventQueue.take()), ["idle"])
    }

    /// `.wake` を挟んでも、送った値はすべて入れた順に取り出される。
    func testMessagesKeepOrderAcrossWakes() {
        let eventQueue = LoopEventQueue<Int>()
        for value in 0..<100 {
            eventQueue.post(.message(value))
            eventQueue.post(.wake)
        }

        let events = eventQueue.take()
        let messages = events.compactMap { event -> Int? in
            if case .message(let value) = event { return value }
            return nil
        }
        XCTAssertEqual(messages, Array(0..<100))
        XCTAssertEqual(labels(of: events).filter { $0 == "wake" }.count, 1)
    }

    /// 取り出した後に入れた `.wake` は、次に取り出すときにまた 1 つ渡る。
    func testWakeAfterTakeIsDeliveredAgain() {
        let eventQueue = LoopEventQueue<Int>()
        eventQueue.post(.wake)
        _ = eventQueue.take()
        eventQueue.post(.wake)

        XCTAssertEqual(labels(of: eventQueue.take()), ["wake"])
    }

    /// 閉じた後は受け付けず、知らせの `AsyncStream` も終わる。
    func testClosedQueueRejectsEventsAndFinishesArrivals() async {
        let eventQueue = LoopEventQueue<Int>()
        XCTAssertTrue(eventQueue.post(.message(1)))
        eventQueue.close()

        XCTAssertFalse(eventQueue.post(.message(2)))
        var arrivals = 0
        for await _ in eventQueue.arrivals { arrivals += 1 }
        XCTAssertEqual(arrivals, 1)
    }

    // MARK: - 補助

    /// 取り出した `LoopEvent` を、種類の名前に直す。
    ///
    /// - Parameters:
    ///   - events: 名前に直す `LoopEvent`。
    /// - Returns: 種類の名前を、並びを保って並べたもの。
    private func labels(of events: [LoopEvent<Int>]) -> [String] {
        events.map { event in
            switch event {
            case .inputs: return "inputs"
            case .message: return "message"
            case .wake: return "wake"
            case .idle: return "idle"
            }
        }
    }
}
