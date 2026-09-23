import XCTest
@testable import TUIKit

/// `LoopMailbox` が `LoopEvent` をどう溜め、どう取り出すかを確かめる。
final class LoopMailboxTests: XCTestCase {

    /// 取り出される前に何度入れても、`.wake` は 1 つしか溜まらない。
    func testWakesPostedBeforeTakeAreCoalesced() {
        let mailbox = LoopMailbox<Int>()
        for _ in 0..<1_000 { mailbox.post(.wake) }

        XCTAssertEqual(labels(of: mailbox.take()), ["wake"])
        XCTAssertEqual(labels(of: mailbox.take()), [])
    }

    /// 取り出される前に何度入れても、`.idle` は 1 つしか溜まらない。
    func testIdlesPostedBeforeTakeAreCoalesced() {
        let mailbox = LoopMailbox<Int>()
        for _ in 0..<1_000 { mailbox.post(.idle) }

        XCTAssertEqual(labels(of: mailbox.take()), ["idle"])
    }

    /// `.wake` を挟んでも、送った値はすべて入れた順に取り出される。
    func testMessagesKeepOrderAcrossWakes() {
        let mailbox = LoopMailbox<Int>()
        for value in 0..<100 {
            mailbox.post(.message(value))
            mailbox.post(.wake)
        }

        let events = mailbox.take()
        let messages = events.compactMap { event -> Int? in
            if case .message(let value) = event { return value }
            return nil
        }
        XCTAssertEqual(messages, Array(0..<100))
        XCTAssertEqual(labels(of: events).filter { $0 == "wake" }.count, 1)
    }

    /// 取り出した後に入れた `.wake` は、次に取り出すときにまた 1 つ渡る。
    func testWakeAfterTakeIsDeliveredAgain() {
        let mailbox = LoopMailbox<Int>()
        mailbox.post(.wake)
        _ = mailbox.take()
        mailbox.post(.wake)

        XCTAssertEqual(labels(of: mailbox.take()), ["wake"])
    }

    /// 閉じた後は受け付けず、知らせの `AsyncStream` も終わる。
    func testClosedMailboxRejectsEventsAndFinishesArrivals() async {
        let mailbox = LoopMailbox<Int>()
        XCTAssertTrue(mailbox.post(.message(1)))
        mailbox.close()

        XCTAssertFalse(mailbox.post(.message(2)))
        var arrivals = 0
        for await _ in mailbox.arrivals { arrivals += 1 }
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
