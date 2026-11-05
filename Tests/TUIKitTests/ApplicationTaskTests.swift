#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// `TerminalApp.task(sender:)` が呼び出される時点と打ち切られる時点、そこで送った値が画面に出るかを、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationTaskTests: XCTestCase {

    /// `TerminalApp.task(sender:)` で送った値で、`ApplicationOptions.frameInterval` なしでも画面が描き直される。
    func testValueSentFromTaskRedrawsWithoutFrameInterval() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
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

        XCTAssertEqual(app.records, ["task:start", "receive:loaded"])
    }

    /// `TerminalApp.task(sender:)` は、最初の `Application.draw()` の 1 回の後に始まる。
    func testTaskStartsAfterFirstDraw() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
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

    /// イベントループを抜けると `TerminalApp.task(sender:)` の `Task` が打ち切られ、`Application.run()` はそれが終わってから戻る。
    func testTaskIsCancelledAndFinishesBeforeRunReturns() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        app.work = { _ in
            try? await Task.sleep(nanoseconds: 60_000_000_000)
            app.record("task:end:cancelled=\(Task.isCancelled)")
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task {
            try await application.run()
            app.record("run:returned")
        }

        let started = await waitUntil { app.records.contains("task:start") }
        XCTAssertTrue(started, "TerminalApp.task(sender:) が呼び出されない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "task:end:cancelled=true", "run:returned"])
    }

    /// `TerminalApp.task(sender:)` が打ち切りに応じない間も、`Application.run()` は端末デバイスの termios を起動前へ戻しており、その処理が終わるまで戻らない。
    func testTerminalIsRestoredWhileTaskIgnoresCancellation() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        var release: CheckedContinuation<Void, Never>?
        // `Task.sleep` で待ってはいけない。打ち切られるとすぐに戻るので、打ち切りに応じない処理にならない。
        app.work = { _ in
            await withCheckedContinuation { release = $0 }
        }
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task {
            try await application.run()
            app.record("run:returned")
        }

        let started = await waitUntil { release != nil }
        XCTAssertTrue(started, "TerminalApp.task(sender:) が呼び出されない")
        XCTAssertFalse(isCanonical(pty.slave), "イベントループを回している間に raw モードになっていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        let restored = await waitUntil { isCanonical(pty.slave) }
        XCTAssertTrue(restored, "TerminalApp.task(sender:) が終わるまで、端末デバイスが raw モードのまま残っている")
        XCTAssertFalse(app.records.contains("run:returned"), "TerminalApp.task(sender:) が終わる前に Application.run() が戻った")

        release?.resume()
        try await waitForLoop(loop)

        XCTAssertEqual(app.records, ["task:start", "run:returned"])
    }

    /// 打ち切られた後に `MessageSender.send(_:)` で送った値は届かず、`false` が返る。
    func testValueSentAfterCancellationIsRejected() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
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

    /// 最初の `.resize` で `TerminalApp.isFinished` が `true` になったときは、`TerminalApp.task(sender:)` を呼び出さない。
    func testTaskIsNotStartedWhenFinishedOnFirstResize() async throws {
        let pty = try TaskPseudoTerminal()
        defer { pty.close() }

        let app = TaskRecordingApp()
        app.finishesOnFirstResize = true
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)

        XCTAssertEqual(app.records, [])
        XCTAssertEqual(app.drawCount, 0)
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
private enum TaskMessage: Sendable {
    case loaded
}

/// 値が届く前に画面へ出ている文字列。
private let waitingText = "WAITING"

/// `TaskMessage.loaded` が届いた後に画面へ出る文字列。
private let loadedText = "LOADED"

/// `TerminalApp.task(sender:)` と `TerminalApp.receive(_:)` が呼び出された順を記録し、`q` で終了する `TerminalApp` に準拠する型。
private final class TaskRecordingApp: TerminalApp {

    /// 呼び出されたメソッドを、呼び出された順に文字列で並べたもの。
    private(set) var records: [String] = []
    /// `TerminalApp.body` が評価された回数。1 回の描画で 1 回評価される。
    private(set) var drawCount = 0
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// `TaskMessage.loaded` を受け取ったら `true`。
    private var hasLoaded = false

    /// `TerminalApp.task(sender:)` の中で実行する処理。
    var work: (MessageSender<TaskMessage>) async -> Void = { _ in }
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

    func receive(_ message: TaskMessage) -> EventResult {
        hasLoaded = true
        record("receive:loaded")
        return .handled
    }

    func task(sender: MessageSender<TaskMessage>) async {
        record("task:start")
        await work(sender)
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
private final class TaskPseudoTerminal {
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
