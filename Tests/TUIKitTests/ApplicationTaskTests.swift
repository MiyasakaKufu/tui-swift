import Foundation
import XCTest
@testable import TUIKit

/// `View.task(_:)` の `Task` が始まる時点と打ち切られる時点を、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationTaskTests: XCTestCase {

    /// `View.task(_:)` の `Task` は、最初の `Application.draw()` の 1 回の後に始まる。
    func testTaskStartsAfterFirstDraw() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        app.recorder.work = {
            app.recorder.drawCountAtStart = app.recorder.drawCount
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.recorder.drawCountAtStart != nil }
        XCTAssertTrue(started, "View.task(_:) の Task が始まらない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.drawCountAtStart, 1)
    }

    /// 再描画しても、`View.task(_:)` の `Task` は始め直さない。
    func testTaskIsNotRestartedByRedraw() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.recorder.records == ["task:start"] }
        XCTAssertTrue(started, "View.task(_:) の Task が始まらない")

        let drawsBefore = app.recorder.drawCount
        pty.write(UInt8(ascii: "r"))
        let redrew = await waitUntil { app.recorder.drawCount > drawsBefore }
        XCTAssertTrue(redrew, "キーで再描画されない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.records, ["task:start"])
    }

    /// `View.task(_:)` を付けた `View` が描かれなくなると、その `Task` が打ち切られる。
    func testTaskIsCancelledWhenViewDisappears() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        app.recorder.work = {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            app.recorder.records.append("task:end:cancelled=\(Task.isCancelled)")
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.recorder.records.contains("task:start") }
        XCTAssertTrue(started, "View.task(_:) の Task が始まらない")

        pty.write(UInt8(ascii: "h"))
        let ended = await waitUntil { app.recorder.records.count >= 2 }
        XCTAssertTrue(ended, "View.task(_:) を付けた View が描かれなくなっても Task が打ち切られない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.records, ["task:start", "task:end:cancelled=true"])
    }

    /// イベントループを抜けると、`View.task(_:)` の `Task` が打ち切られる。
    func testTaskIsCancelledWhenLoopEnds() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        app.recorder.work = {
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            app.recorder.records.append("task:end:cancelled=\(Task.isCancelled)")
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.recorder.records.contains("task:start") }
        XCTAssertTrue(started, "View.task(_:) の Task が始まらない")

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)

        let ended = await waitUntil { app.recorder.records.count >= 2 }
        XCTAssertTrue(ended, "View.task(_:) の Task が打ち切られない")
        XCTAssertEqual(app.recorder.records, ["task:start", "task:end:cancelled=true"])
    }

    /// `View.task(_:)` の `Task` が打ち切りに応じなくても、`Application.run()` はその処理が終わるのを待たずに戻る。
    func testRunReturnsWithoutWaitingForTaskThatIgnoresCancellation() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        var release: CheckedContinuation<Void, Never>?
        // `Task.sleep` で待ってはいけない。打ち切られるとすぐに戻るので、打ち切りに応じない処理にならない。
        app.recorder.work = {
            await withCheckedContinuation { release = $0 }
            app.recorder.records.append("task:end")
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { release != nil }
        XCTAssertTrue(started, "View.task(_:) の Task が始まらない")

        // 一定時間後に処理を終わらせるのをやめてはいけない。`Application.run()` が処理の終わりを待つ実装に戻ると、このテストは失敗せずに止まり続ける。
        let fallback = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            release?.resume()
            release = nil
        }
        defer { fallback.cancel() }

        pty.write(UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.records, ["task:start"], "Application.run() が View.task(_:) の Task の終わりを待った")
        release?.resume()
        release = nil
    }

    /// 最初の `.resize` で `TerminalApp.isFinished` が `true` になったときは、`View.task(_:)` の `Task` を始めない。
    func testTaskIsNotStartedWhenFinishedOnFirstResize() async throws {
        let pty = try DrainedPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp(finishesOnFirstResize: true)
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.records, [])
        XCTAssertEqual(app.recorder.drawCount, 0)
    }

    // MARK: - 補助

    /// 問い合わせを送らず、代替画面へも切り替えない設定。
    private var testOptions: ApplicationOptions {
        ApplicationOptions(
            usesAlternateScreen: false,
            usesBracketedPaste: false,
            usesKeyboardProtocol: false
        )
    }

    /// 条件が満たされるまで待つ。
    ///
    /// - Parameters:
    ///   - timeout: 待つ秒数の上限。
    ///   - condition: 満たされたかを返す処理。
    /// - Returns: 時間内に満たされれば `true`。
    private func waitUntil(timeout: Double = 5, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            // `Thread.sleep` で待つと、アクタが止まってイベントループが進まない。
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }
}

// `State` を付けたプロパティに置きたくなるが、`TerminalApp.body` の中で書き込むことになり、`State` が禁じる描画の中での代入になる。
/// テスト用の `TerminalApp` に準拠する型が、起きたことを書き込むクラス。
@MainActor
private final class TaskRecorder {
    /// 起きたことを、起きた順に文字列で並べたもの。
    var records: [String] = []
    /// `TerminalApp.body` が評価された回数。1 回の描画で 1 回評価される。
    var drawCount = 0
    /// `View.task(_:)` の `Task` が始まった時点の `TaskRecorder.drawCount`。まだ始まっていなければ `nil`。
    var drawCountAtStart: Int?
    /// `View.task(_:)` の `Task` の中で実行する処理。
    var work: @MainActor () async -> Void = {}
}

/// `View.task(_:)` を付けた `Text` を描き、`h` でその `Text` を隠し、`q` で終了する `TerminalApp` に準拠する型。
private struct TaskRecordingApp: TerminalApp {

    /// 起きたことを書き込む先。
    let recorder = TaskRecorder()
    /// `Application` を終了するかどうか。
    @State private(set) var isFinished = false

    @State private var isHidden = false
    @State private var redrawCount = 0
    private let finishesOnFirstResize: Bool

    /// 最初の `.resize` で終了するかを決めて作る。
    ///
    /// - Parameters:
    ///   - finishesOnFirstResize: 最初の `.resize` で終了するなら `true`。
    init(finishesOnFirstResize: Bool) {
        self.finishesOnFirstResize = finishesOnFirstResize
    }

    /// 最初の `.resize` で終了しないものとして作る。
    init() {
        self.init(finishesOnFirstResize: false)
    }

    var body: some View {
        recorder.drawCount += 1
        let recorder = self.recorder
        return VStack {
            Text("再描画 \(redrawCount)")
            if !isHidden {
                Text("Task あり").task {
                    recorder.records.append("task:start")
                    await recorder.work()
                }
            }
        }
    }

    func handle(_ event: InputEvent) -> EventResult {
        switch event {
        case .resize:
            if finishesOnFirstResize { isFinished = true }
            return .handled
        case .key(let keyEvent) where keyEvent.key == .character("h"):
            isHidden = true
            return .handled
        case .key(let keyEvent) where keyEvent.key == .character("r"):
            redrawCount += 1
            return .handled
        case .key(let keyEvent) where keyEvent.key == .character("q"):
            isFinished = true
            return .handled
        default:
            return .ignored
        }
    }
}
