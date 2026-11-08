#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// キーと、ループの外から呼び出した `Application.stop()`・`Application.suspend()` がループへ渡るかと、`TerminalApp.isFinished` でループが終わるかを、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationLoopTests: XCTestCase {

    private var captured = ""

    /// 端末エミュレータへの問い合わせの応答を待つ間に届いたキーも、ループへ渡る。
    func testKeysArrivingDuringTerminalQueryReachTheLoop() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = LoopRecordingApp()
        let application = Application(
            root: app,
            options: ApplicationOptions(
                usesAlternateScreen: false,
                usesBracketedPaste: false,
                usesKeyboardProtocol: true
            ),
            terminal: pty.terminal()
        )
        let loop = Task { try await application.run() }

        // 問い合わせが出てから書く。先に書くと raw モードへの切り替えで捨てられる。
        let asked = await waitUntil(timeout: 5) { self.captured.contains(ANSI.queryDeviceAttributes) }
        XCTAssertTrue(asked, "問い合わせが出ない")

        // 応答は書き込まない。書き込むと待ちが早く終わり、待ちの間に届いたことにならない。
        writeByte(pty.master, UInt8(ascii: "a"))

        let reached = await waitUntil(timeout: 5) { app.recorder.records == ["key:a"] }
        XCTAssertTrue(reached, "問い合わせの間に届いたキーが落ちている: \(app.recorder.records)")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// 1 回でまとめて届いたキーは、1 回だけ描き直す。
    func testKeysReadTogetherAreDrawnOnce() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = LoopRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil(timeout: 5) { app.recorder.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        let drawsBefore = app.recorder.drawCount

        // 1 回の `write(2)` で書く。分けると別々の回に読まれ、まとめて届いたことにならない。
        writeBytes(pty.master, Array("abc".utf8))
        let reached = await waitUntil(timeout: 5) { app.recorder.records.count == 3 }
        XCTAssertTrue(reached, "キーが届かない: \(app.recorder.records)")
        // キーが届いた時点で数えてはいけない。前の描画から `ApplicationOptions.maximumFrameRate` の間隔が経っていなければ、再描画は後に回る。
        let redrew = await waitUntil(timeout: 5) { app.recorder.drawCount > drawsBefore }
        XCTAssertTrue(redrew, "キーで再描画されない")
        // 待たずに数えてはいけない。余分な再描画は後の周回で起きるので、見逃す。
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(app.recorder.drawCount - drawsBefore, 1)

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// ループの外から呼び出した `Application.stop()` で、キーを待たずにループが終わる。
    func testStopFromOutsideLoopEndsLoopWithoutKeys() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = LoopRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // `Application.stop()` を最初の描画より前に呼び出してはいけない。`Application.run()` が始まる前に呼び出すことになり、`Application.run()` が `Application.isRunning` を立て直すので、ループが終わらない。
        let drew = await waitUntil(timeout: 5) { app.recorder.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        application.stop()
        try await waitForLoop(loop)
    }

    /// ループの外から呼び出した `Application.suspend()` で、キーを待たずに再開後の画面を描き直す。
    func testSuspendFromOutsideLoopRedrawsWithoutKeys() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = LoopRecordingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        // 本当に止めるとテストプロセスまで止まるので、止める処理だけ差し替える。
        application.stopProcess = {}
        let loop = Task { try await application.run() }

        let drew = await waitUntil(timeout: 5) { app.recorder.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        let drawsBefore = app.recorder.drawCount

        application.suspend()

        // 描き直されるまで、キーのバイトを書いてはいけない。キーで描き直されたのかどうかが分からなくなる。
        let redrew = await waitUntil(timeout: 5) { app.recorder.drawCount > drawsBefore }
        XCTAssertTrue(redrew, "再開した後に画面が描き直されていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    // MARK: - `TerminalApp.isFinished`

    /// `View.onKeyPress(_:action:)` のクロージャで `TerminalApp.isFinished` を `true` にすると、同じ時点に届いていた残りのキーを渡さずにループが終わる。
    func testFinishingInKeyPressActionSkipsRemainingKeys() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = KeyPressFinishingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 最初の描画より前に書いてはいけない。フォーカスを持つ `View` が決まる前にキーが届き、`View.onKeyPress(_:action:)` のクロージャが呼び出されない。
        let drew = await waitUntil(timeout: 5) { app.recorder.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")

        writeBytes(pty.master, [UInt8(ascii: "a"), UInt8(ascii: "b")])
        try await waitForLoop(loop)

        XCTAssertEqual(app.recorder.handledKeys, [])
    }

    /// 最初の `.resize` を受け取った `TerminalApp.handle(_:)` で `TerminalApp.isFinished` を `true` にすると、描かずにループが終わる。
    func testFinishingOnFirstResizeEndsLoopWithoutDrawing() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let app = ResizeFinishingApp()
        let application = Application(root: app, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await waitForLoop(loop)
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

    /// pty の出力を読み続け、`captured` へ足していく `Task` を作る。
    ///
    /// - Parameters:
    ///   - reader: 読み取り元。
    /// - Returns: 読み続ける `Task`。テストの終わりに打ち切る。
    private func startCapturing(_ reader: OutputReader) -> Task<Void, Never> {
        Task {
            for await chunk in reader.stream {
                captured += String(decoding: chunk, as: UTF8.self)
            }
        }
    }

    /// 条件が満たされるまで待つ。
    ///
    /// - Parameters:
    ///   - timeout: 待つ秒数の上限。
    ///   - condition: 満たされたかを返す処理。
    /// - Returns: 時間内に満たされれば `true`。
    private func waitUntil(timeout: Double, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
            // `Thread.sleep` で待つと、アクタが止まってイベントループが進まない。
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        return true
    }
}

/// 画面へ出す文字列。
private let waitingText = "WAITING"

// `State` を付けたプロパティに置きたくなるが、`TerminalApp.body` の中で書き込むことになり、`State` が禁じる描画の中での代入になる。
/// テスト用の `TerminalApp` に準拠する型が、受け取ったものを書き込むクラス。
@MainActor
private final class LoopRecorder {
    /// 受け取ったキーを、届いた順に文字列で並べたもの。
    var records: [String] = []
    /// `TerminalApp.handle(_:)` が受け取ったキーの文字を、届いた順に並べたもの。
    var handledKeys: [Character] = []
    /// 最初の描画が終わったら `true`。
    var hasDrawnOnce = false
    /// `TerminalApp.body` が評価された回数。1 回の描画で 1 回評価される。
    var drawCount = 0
}

/// 届いたキーを記録し、`q` で終了する `TerminalApp` に準拠する型。
private struct LoopRecordingApp: TerminalApp {

    /// 受け取ったものを書き込む先。
    let recorder = LoopRecorder()
    /// `Application` を終了するかどうか。
    @State private(set) var isFinished = false

    var body: some View {
        recorder.hasDrawnOnce = true
        recorder.drawCount += 1
        return Text(waitingText)
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let keyEvent) = event,
              case .character(let character) = keyEvent.key
        else {
            return .ignored
        }
        if character == "q" {
            isFinished = true
            return .handled
        }
        recorder.records.append("key:\(character)")
        return .handled
    }
}

/// フォーカスを受け取る `ListView` に付けた `View.onKeyPress(_:action:)` のクロージャで、`a` を受け取ったら終了する `TerminalApp` に準拠する型。
private struct KeyPressFinishingApp: TerminalApp {

    /// 受け取ったものを書き込む先。
    let recorder = LoopRecorder()
    /// `Application` を終了するかどうか。
    @State private(set) var isFinished = false

    @State private var listState = ListState()

    var body: some View {
        recorder.hasDrawnOnce = true
        let finish = $isFinished
        return ListView(items: [waitingText], state: listState)
            .onKeyPress(.character("a")) {
                finish.wrappedValue = true
                return .handled
            }
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let keyEvent) = event,
              case .character(let character) = keyEvent.key
        else {
            return .ignored
        }
        recorder.handledKeys.append(character)
        return .handled
    }
}

/// 最初の `.resize` で終了する `TerminalApp` に準拠する型。
private struct ResizeFinishingApp: TerminalApp {

    /// 受け取ったものを書き込む先。
    let recorder = LoopRecorder()
    /// `Application` を終了するかどうか。
    @State private(set) var isFinished = false

    var body: some View {
        recorder.drawCount += 1
        return Text(waitingText)
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .resize = event else { return .ignored }
        isFinished = true
        return .handled
    }
}

/// テスト用の疑似端末。
///
/// - Warning: master は `OutputReader` で読み続ける。読まずに溜まったバイト列がカーネルの上限に達すると、slave への `write(2)` や、出力の掃き出しを待つ `tcsetattr(TCSAFLUSH)` が戻らなくなる。
private final class PseudoTerminal {
    enum Failure: Error {
        case unavailable(errno: Int32)
    }

    let master: Int32
    let slave: Int32
    private var isClosed = false

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard ctui_test_open_pty(&master, &slave) == 0 else {
            throw Failure.unavailable(errno: errno)
        }
        self.master = master
        self.slave = slave
    }

    deinit {
        close()
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
        closeDescriptor(slave)
        closeDescriptor(master)
    }
}

/// pty の master に溜まる出力を読み続け、読んだものを `AsyncStream` へ流す。
private final class OutputReader {

    // 読んだ内容をこのクラスに持たせてはいけない。読むスレッドとテストの両方から触ることになり、
    // データ競合になる。
    /// 読んだバイト列が届く `AsyncStream`。
    let stream: AsyncStream<[UInt8]>

    /// 読み取り元を指定して読み始める。
    ///
    /// - Parameters:
    ///   - descriptor: 読み取り元のファイル記述子。
    init(descriptor: Int32) {
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
        self.stream = stream

        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = buffer.withUnsafeMutableBytes { raw in
                    read(descriptor, raw.baseAddress, raw.count)
                }
                if count > 0 {
                    if case .terminated = continuation.yield(Array(buffer[0..<count])) { return }
                    continue
                }
                if count < 0 && errno == EINTR { continue }
                continuation.finish()
                return
            }
        }
    }
}

/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    guard descriptor >= 0 else { return }
    close(descriptor)
}

/// tty のウィンドウサイズを設定する。
///
/// - Parameters:
///   - descriptor: 設定する tty のファイル記述子。
///   - size: 設定するサイズ。
/// - Returns: 成功なら `0`。
private func setTerminalSize(_ descriptor: Int32, _ size: Size) -> Int32 {
    ctui_test_set_terminal_size(descriptor, Int32(size.width), Int32(size.height))
}

/// 記述子へ、まとめて 1 回で書く。
///
/// - Parameters:
///   - descriptor: 書き込む先のファイル記述子。
///   - bytes: 書き込むバイト列。
private func writeBytes(_ descriptor: Int32, _ bytes: [UInt8]) {
    var buffer = bytes
    _ = write(descriptor, &buffer, buffer.count)
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
