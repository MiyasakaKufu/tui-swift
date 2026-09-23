import XCTest

extension XCTestCase {
    /// `run()` を回している `Task` が戻るのを、決めた時間だけ待つ。
    ///
    /// 時間内に戻らなければ失敗として記録し、`Task` を打ち切る。打ち切られた `run()` は、
    /// 次の `LoopEvent` を待つ `for await` を抜けて戻る。
    ///
    /// - Parameters:
    ///   - loop: `run()` を回している `Task`。
    ///   - timeout: 待つ時間（秒）。
    ///   - file: 失敗として記録するファイル。
    ///   - line: 失敗として記録する行。
    /// - Throws: `run()` が投げたもの。
    @MainActor
    func waitForLoop(
        _ loop: Task<Void, Error>,
        timeout: Double = 5,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        // 待つだけにしてはいけない。守っている不具合が戻ると `run()` が戻らず、
        // このテストが失敗する代わりに、テスト全体が CI の制限時間まで止まる。
        let watchdog = Task {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            XCTFail("\(timeout) 秒以内に run() が戻らない", file: file, line: line)
            loop.cancel()
        }
        defer { watchdog.cancel() }
        try await loop.value
    }
}
