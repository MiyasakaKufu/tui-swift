import Foundation
import XCTest
@testable import TUIKit

/// Linux の Swift 6.0 で `Mutex` が使えるかを確かめる spike。
final class MutexSpikeTests: XCTestCase {

    /// 複数のスレッドから足しても、値が欠けない。
    func testAppendsFromManyThreadsAllArrive() {
        let counter = MutexSpikeCounter()
        let group = DispatchGroup()
        for thread in 0..<4 {
            group.enter()
            Thread.detachNewThread {
                for value in 0..<1_000 { counter.append(thread * 1_000 + value) }
                group.leave()
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)
        XCTAssertEqual(counter.takeAll().sorted(), Array(0..<4_000))
    }

    /// `Task` からも、`@unchecked` なしで渡して使える。
    func testUsableFromTasks() async {
        let counter = MutexSpikeCounter()
        await withTaskGroup(of: Void.self) { group in
            for value in 0..<100 {
                group.addTask { counter.append(value) }
            }
        }
        XCTAssertEqual(counter.takeAll().sorted(), Array(0..<100))
    }
}
