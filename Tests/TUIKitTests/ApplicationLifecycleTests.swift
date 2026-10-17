#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// `TerminalApp.task(sender:)`・`TerminalApp.willSuspend()`・`TerminalApp.didResume()`・`TerminalApp.didTerminate(_:)` が呼び出される時点と順序を、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationLifecycleTests: XCTestCase {

    // MARK: - `TerminalApp.task(sender:)`

    /// `TerminalApp.task(sender:)` で送った値で、`ApplicationOptions.frameInterval` なしでも画面が描き直される。
    func testValueSentFromTaskRedrawsWithoutFrameInterval() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        app.work = { sender in
            sender.send(.loaded)
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 描き直されたかを、キーを書いた後で確かめてはいけない。キーで描き直されたのかどうかが分からなくなる。
        let redrew = await waitUntil { pty.output.contains(loadedText) }
        XCTAssertTrue(redrew, "TerminalApp.task(sender:) で送った値が届いた後に描き直されていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "receive:loaded", "didTerminate:finished"])
    }

    /// `TerminalApp.task(sender:)` は、最初の `Application.draw()` の 1 回の後に始まる。
    func testTaskStartsAfterFirstDraw() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        var drawCountAtStart: Int?
        app.work = { _ in
            drawCountAtStart = app.drawCount
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { drawCountAtStart != nil }
        XCTAssertTrue(started, "TerminalApp.task(sender:) が呼び出されない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(drawCountAtStart, 1)
    }

    /// イベントループを抜けると `TerminalApp.task(sender:)` の `Task` が打ち切られ、それが終わってから `TerminalApp.didTerminate(_:)` が呼び出される。
    func testTaskIsCancelledAndFinishesBeforeDidTerminate() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        app.work = { _ in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            app.record("task:end:cancelled=\(Task.isCancelled)")
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.records.contains("task:start") }
        XCTAssertTrue(started, "TerminalApp.task(sender:) が呼び出されない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "task:end:cancelled=true", "didTerminate:finished"])
    }

    /// 打ち切られた後に `MessageSender.send(_:)` で送った値は届かず、`false` が返る。
    func testValueSentAfterCancellationIsRejected() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        var acceptedAfterCancellation: Bool?
        app.work = { sender in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            acceptedAfterCancellation = sender.send(.loaded)
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let started = await waitUntil { app.records.contains("task:start") }
        XCTAssertTrue(started, "TerminalApp.task(sender:) が呼び出されない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(acceptedAfterCancellation, false)
        XCTAssertFalse(app.records.contains("receive:loaded"))
    }

    /// 最初の `.resize` で `TerminalApp.isFinished` が `true` になったときは、`TerminalApp.task(sender:)` を呼び出さずに `TerminalApp.didTerminate(_:)` を呼び出す。
    func testTaskIsNotStartedWhenFinishedOnFirstResize() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        app.finishesOnFirstResize = true
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["didTerminate:finished"])
        XCTAssertEqual(app.drawCount, 0)
    }

    // MARK: - `TerminalApp.didTerminate(_:)`

    /// `TerminalApp.didTerminate(_:)` は、端末デバイスの termios を起動前へ戻した後に呼び出される。
    func testDidTerminateIsCalledAfterTerminalIsRestored() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        var isCanonicalAtTermination: Bool?
        app.onTerminate = {
            isCanonicalAtTermination = isCanonical(pty.slave)
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        XCTAssertFalse(isCanonical(pty.slave), "イベントループを回している間に raw モードになっていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(isCanonicalAtTermination, true)
    }

    /// `TerminalApp.handle(_:)` が `.ignored` を返した Ctrl+C で抜けると、`.controlC` を渡す。
    func testDidTerminateReceivesControlC() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        writeByte(pty.master, 0x03)
        try await waitForLoop(loop)

        XCTAssertEqual(app.reason, .controlC)
    }

    /// 終了シグナルで抜けると、届いたシグナルの番号を `.signal(_:)` で渡す。
    func testDidTerminateReceivesSignalNumber() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        app.work = { _ in
            kill(getpid(), SIGHUP)
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)

        XCTAssertEqual(app.reason, .signal(SIGHUP))
    }

    /// `Application.stop()` で抜けると、`.stopped` を渡す。
    func testDidTerminateReceivesStopped() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 最初の描画より前に呼び出してはいけない。`Application.run()` が `Application.stopReason` を消すので、ループが終わらない。
        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        application.stop()
        try await waitForLoop(loop)

        XCTAssertEqual(app.reason, .stopped)
    }

    /// `Application.run()` を呼び出している `Task` が打ち切られて抜けると、`.cancelled` を渡す。
    func testDidTerminateReceivesCancelled() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        loop.cancel()
        try await waitForLoop(loop)

        XCTAssertEqual(app.reason, .cancelled)
    }

    // MARK: - `TerminalApp.willSuspend()`・`TerminalApp.didResume()`

    /// 一時停止すると、端末デバイスの termios を戻した後に `TerminalApp.willSuspend()` を、raw モードへ戻した後に `TerminalApp.didResume()` を呼び出し、その後に描き直す。
    func testSuspendCallsWillSuspendAndDidResumeInOrder() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        var isCanonicalBeforeSuspending: Bool?
        var isCanonicalAfterResuming: Bool?
        var drawCountAtResume: Int?
        app.onWillSuspend = {
            isCanonicalBeforeSuspending = isCanonical(pty.slave)
        }
        app.onDidResume = {
            isCanonicalAfterResuming = isCanonical(pty.slave)
            drawCountAtResume = app.drawCount
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        // 本当に止めるとテストプロセスまで止まるので、止める処理だけ差し替える。
        application.stopProcess = {}
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        // Ctrl+Z を書かなければならない。`Application.suspend()` を直接呼び出すと、`ApplicationOptions.suspendsOnControlZ` の経路を通らない。
        writeByte(pty.master, 0x1A)
        let redrew = await waitUntil { drawCountAtResume.map { app.drawCount > $0 } ?? false }
        XCTAssertTrue(redrew, "再開した後に描き直されていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "willSuspend", "didResume", "didTerminate:finished"])
        XCTAssertEqual(isCanonicalBeforeSuspending, true)
        XCTAssertEqual(isCanonicalAfterResuming, false)
    }

    /// SIGTSTP を経ずに SIGCONT だけが届いたとき（捕まえられない SIGSTOP で止められたときなど）は、`TerminalApp.didResume()` だけを呼び出す。
    func testContinueWithoutSuspendCallsOnlyDidResume() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        let app = LifecycleRecordingApp()
        app.work = { _ in
            kill(getpid(), SIGCONT)
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let resumed = await waitUntil { app.records.contains("didResume") }
        XCTAssertTrue(resumed, "SIGCONT で TerminalApp.didResume() が呼び出されない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "didResume", "didTerminate:finished"])
    }

    /// 一時停止から再開したときに端末デバイスを raw モードへ戻せなければ、`TerminalApp.didResume()` を呼び出さず、`.resumeFailed` を渡す。
    func testResumeFailureEndsLoopWithResumeFailed() async throws {
        let pty = try LifecyclePseudoTerminal()
        defer { pty.close() }

        // `Application.stopProcess` で `LifecyclePseudoTerminal.slave` そのものを閉じてはいけない。`LifecyclePseudoTerminal.close()` がもう一度閉じるので、その間に同じ番号を使った別の記述子を閉じてしまう。
        let descriptor = dup(pty.slave)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        let app = LifecycleRecordingApp()
        let application = Application(
            root: app,
            options: testOptions,
            terminal: Terminal(input: descriptor, output: descriptor)
        )
        application.stopProcess = { closeDescriptor(descriptor) }
        let loop = Task { try await application.run() }

        let drew = await waitUntil { app.drawCount > 0 }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        writeByte(pty.master, 0x1A)
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "willSuspend", "didTerminate:resumeFailed"])
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

/// テストから送る値。
private enum LifecycleMessage: Sendable {
    case loaded
}

/// 値が届く前に画面へ出ている文字列。
private let waitingText = "WAITING"

/// `LifecycleMessage.loaded` が届いた後に画面へ出る文字列。
private let loadedText = "LOADED"

/// `TerminalApp.task(sender:)` などが呼び出された順を記録し、`q` で終了する `TerminalApp` に準拠する型。
private final class LifecycleRecordingApp: TerminalApp {

    /// 呼び出されたメソッドを、呼び出された順に文字列で並べたもの。
    private(set) var records: [String] = []
    /// `TerminalApp.didTerminate(_:)` が受け取った理由。呼び出されていなければ `nil`。
    private(set) var reason: TerminationReason?
    /// `TerminalApp.body` が評価された回数。1 回の描画で 1 回評価される。
    private(set) var drawCount = 0
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// `LifecycleMessage.loaded` を受け取ったら `true`。
    private var hasLoaded = false

    /// `TerminalApp.task(sender:)` の中で実行する処理。
    var work: (MessageSender<LifecycleMessage>) async -> Void = { _ in }
    /// `TerminalApp.willSuspend()` の中で実行する処理。
    var onWillSuspend: () -> Void = {}
    /// `TerminalApp.didResume()` の中で実行する処理。
    var onDidResume: () -> Void = {}
    /// `TerminalApp.didTerminate(_:)` の中で実行する処理。
    var onTerminate: () -> Void = {}
    /// 最初の `.resize` で終了するなら `true`。
    var finishesOnFirstResize = false

    var body: some View {
        drawCount += 1
        return Text(hasLoaded ? loadedText : waitingText)
    }

    func handle(_ event: InputEvent) -> EventResult {
        switch event {
        case .resize:
            if finishesOnFirstResize { isFinished = true }
            return .handled
        case .key(let keyEvent) where keyEvent.key == .character("q"):
            isFinished = true
            return .handled
        default:
            return .ignored
        }
    }

    func receive(_ message: LifecycleMessage) -> EventResult {
        hasLoaded = true
        record("receive:loaded")
        return .handled
    }

    func task(sender: MessageSender<LifecycleMessage>) async {
        record("task:start")
        await work(sender)
    }

    func willSuspend() {
        record("willSuspend")
        onWillSuspend()
    }

    func didResume() {
        record("didResume")
        onDidResume()
    }

    func didTerminate(_ reason: TerminationReason) {
        self.reason = reason
        record("didTerminate:\(reason)")
        onTerminate()
    }

    /// 呼び出されたメソッドを記録する。
    ///
    /// - Parameters:
    ///   - entry: 記録する文字列。
    func record(_ entry: String) {
        records.append(entry)
    }
}

/// テスト用の疑似端末。master を `OutputDrain` で読み続ける。
private final class LifecyclePseudoTerminal {
    enum Failure: Error {
        case unavailable(errno: Int32)
    }

    let master: Int32
    let slave: Int32

    private let drain: OutputDrain
    private var isClosed = false

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard ctui_test_open_pty(&master, &slave) == 0 else {
            throw Failure.unavailable(errno: errno)
        }
        self.master = master
        self.slave = slave
        XCTAssertEqual(ctui_test_set_terminal_size(master, 40, 6), 0)
        drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
    }

    deinit {
        close()
    }

    /// master から読んだ内容。
    var output: String {
        drain.output
    }

    /// slave を入出力に使う `Terminal` を作る。
    ///
    /// - Returns: slave につながった `Terminal`。
    @MainActor
    func terminal() -> Terminal {
        Terminal(input: slave, output: slave)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        // 読み取りスレッドを止める前に閉じてはいけない。`poll(2)` の中に残ったスレッドが、次に開いた疑似端末の出力を横取りする。
        drain.stop()
        closeDescriptor(slave)
        closeDescriptor(master)
    }
}

/// 端末デバイスが canonical モード（raw モードでない）かを返す。
///
/// - Parameters:
///   - descriptor: 調べる端末デバイスのファイル記述子。
/// - Returns: `ICANON` が立っていれば `true`。
private func isCanonical(_ descriptor: Int32) -> Bool {
    var attributes = termios()
    guard tcgetattr(descriptor, &attributes) == 0 else { return false }
    return attributes.c_lflag & tcflag_t(ICANON) != 0
}

// クラスの中から `close(2)` は直接呼び出せない。メンバーの `close()` が先に見つかる。
/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}

/// 記述子へ 1 バイト書く。
///
/// - Parameters:
///   - descriptor: 書き込む先のファイル記述子。
///   - byte: 書き込むバイト。
private func writeByte(_ descriptor: Int32, _ byte: UInt8) {
    var value = byte
    _ = write(descriptor, &value, 1)
}
