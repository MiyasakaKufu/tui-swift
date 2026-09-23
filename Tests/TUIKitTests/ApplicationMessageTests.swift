#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// 外部から届いたイベントがイベントループへ渡るかを、疑似端末（pty）の上で確かめる。
@MainActor
final class ApplicationMessageTests: XCTestCase {

    private var captured = ""

    /// 別スレッドから送ったイベントで、`frameInterval` なしでも画面が更新される。
    func testMessageFromAnotherThreadUpdatesScreenWithoutFrameInterval() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent()
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let sender = application.sender
        let loop = Task { try await application.run() }

        // 最初の描画より前に送ると、送ったことで描き直されたのか確かめられない。
        let drewBeforeSending = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drewBeforeSending, "最初の描画が終わらない")

        Thread.detachNewThread { sender.send(.arrived) }

        // 画面が変わるまで、キーのバイトを書いてはいけない。
        // 送ったイベントだけで変わることを確かめているので、キーで起きたのかどうかが分からなくなる。
        let drew = await waitUntil(timeout: 5) { self.captured.contains(arrivedText) }
        XCTAssertTrue(drew, "送ったイベントが届いた後に画面が描き直されていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertEqual(component.messages, [.arrived])
    }

    /// 複数のスレッドから同時に送っても、すべてのイベントが届く。
    func testMessagesFromManyThreadsAllArrive() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let total = 200
        let component = MessageRecordingComponent(quitsAfter: total)
        let application = Application(
            root: component,
            options: testOptions,
            terminal: pty.terminal()
        )
        let sender = application.sender
        let loop = Task { try await application.run() }

        let drewBeforeSending = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drewBeforeSending, "最初の描画が終わらない")

        for _ in 0..<4 {
            Thread.detachNewThread {
                for _ in 0..<(total / 4) { sender.send(.first) }
            }
        }

        try await waitForLoop(loop)

        XCTAssertEqual(component.messages.count, total)
    }

    /// キー入力と外部イベントの順序が保たれる。
    func testInputAndMessagesKeepOrder() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent(quitsAfter: 4)
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let sender = application.sender
        let loop = Task { try await application.run() }

        // 最初の描画を待たずにキーのバイトを書くと届かない。
        // raw モードへの切り替えが、まだ読まれていないバイト列を捨てる。
        let drewBeforeSending = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drewBeforeSending, "最初の描画が終わらない")

        // 順序を入れ替えてはいけない。
        // キーを先に書くと、ループがそれを読んだのと送ったのとどちらが先か決まらず、
        // 確かめたい順序そのものが揺れる。
        sender.send(.first)
        writeByte(pty.master, UInt8(ascii: "a"))
        let gotBoth = await waitUntil(timeout: 5) { component.records.count >= 2 }
        XCTAssertTrue(gotBoth, "イベントとキーが届かない")

        // キーが届くのを待たずに送ってはいけない。キーより先に積まれて、逆向きを確かめられなくなる。
        writeByte(pty.master, UInt8(ascii: "b"))
        let gotSecondKey = await waitUntil(timeout: 5) { component.records.count >= 3 }
        XCTAssertTrue(gotSecondKey, "キーが届かない")
        sender.send(.second)

        try await waitForLoop(loop)

        XCTAssertEqual(component.records, ["message:first", "key:a", "key:b", "message:second"])
    }

    /// 端末への問い合わせの応答を待つ間に届いたキーも、ループへ渡る。
    func testKeysArrivingDuringTerminalQueryReachTheLoop() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent()
        let application = Application(
            root: component,
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

        // 応答は返さない。返すと待ちが早く終わり、待ちの間に届いたことにならない。
        writeByte(pty.master, UInt8(ascii: "a"))

        let reached = await waitUntil(timeout: 5) { component.records == ["key:a"] }
        XCTAssertTrue(reached, "問い合わせの間に届いたキーが落ちている: \(component.records)")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)
    }

    /// ループが動いている間の送信は受け付け、終わった後の送信は受け付けない。
    func testSenderReportsWhetherLoopAcceptsMessages() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent()
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let sender = application.sender
        let loop = Task { try await application.run() }

        let drew = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        XCTAssertTrue(sender.send(.first), "動いているループが受け付けない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)

        XCTAssertFalse(sender.send(.second), "終わったループが受け付けている")
    }

    /// 1 回でまとめて届いたキーは、1 回だけ描き直す。
    func testKeysReadTogetherAreDrawnOnce() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent()
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        let drew = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drew, "最初の描画が終わらない")
        let drawsBefore = component.drawCount

        // 1 回の `write(2)` で書く。分けると別々の回に読まれ、まとめて届いたことにならない。
        writeBytes(pty.master, Array("abc".utf8))
        let reached = await waitUntil(timeout: 5) { component.records.count == 3 }
        XCTAssertTrue(reached, "キーが届かない: \(component.records)")
        XCTAssertEqual(component.drawCount - drawsBefore, 1)

        writeByte(pty.master, UInt8(ascii: "q"))
        try await waitForLoop(loop)
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

    /// pty の出力を読み続け、`captured` へ足していく `Task` を起こす。
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

/// テストから送るイベント。
private enum TestMessage: Hashable, Sendable {
    case arrived
    case first
    case second
}

/// イベントが届く前に画面へ出ている文字列。
private let waitingText = "WAITING"

/// イベントが届いた後に画面へ出る文字列。
private let arrivedText = "ARRIVED"

/// 届いたイベントとキーを記録し、決めた数だけ届いたら終了するコンポーネント。
private final class MessageRecordingComponent: Component {

    /// 受け取ったイベントを届いた順に並べたもの。
    private(set) var messages: [TestMessage] = []
    /// 受け取ったイベントとキーを、届いた順に文字列で並べたもの。
    private(set) var records: [String] = []
    /// 最初の描画が終わったら `true`。
    private(set) var hasDrawnOnce = false
    /// `body` が評価された回数。1 回の描画で 1 回評価される。
    private(set) var drawCount = 0

    private let quitsAfter: Int

    /// 受け取る件数を決めて作る。
    ///
    /// - Parameters:
    ///   - quitsAfter: 記録がこの数に達したら終了する。`0` なら自分からは終了しない。
    init(quitsAfter: Int = 0) {
        self.quitsAfter = quitsAfter
    }

    var body: some View {
        hasDrawnOnce = true
        drawCount += 1
        return Text(messages.isEmpty ? waitingText : arrivedText)
    }

    func receive(_ message: TestMessage) -> EventResult {
        messages.append(message)
        return record("message:\(label(of: message))")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let keyEvent) = event,
              case .character(let character) = keyEvent.key
        else {
            return .ignored
        }
        if character == "q" { return .quit }
        return record("key:\(character)")
    }

    /// 届いたものを記録し、終了するかを決める。
    ///
    /// - Parameters:
    ///   - entry: 記録する文字列。
    /// - Returns: 決めた数に達したなら `.quit`、まだなら `.handled`。
    private func record(_ entry: String) -> EventResult {
        records.append(entry)
        return records.count == quitsAfter ? .quit : .handled
    }

    /// イベントを記録用の名前に直す。
    ///
    /// - Parameters:
    ///   - message: 名前を付けるイベント。
    /// - Returns: イベントの名前。
    private func label(of message: TestMessage) -> String {
        switch message {
        case .arrived: return "arrived"
        case .first: return "first"
        case .second: return "second"
        }
    }
}

/// テスト用の疑似端末。
///
/// - Warning: master 側は `OutputReader` で読み続ける。出力バッファが詰まると、
///   slave 側への `write(2)` や、出力の掃き出しを待つ `tcsetattr(TCSAFLUSH)` が返らなくなる。
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

    /// slave 側を入出力に使う `Terminal` を作る。
    ///
    /// - Returns: slave 側につながった `Terminal`。
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

/// pty の master 側に溜まる出力を読み続け、読んだものを `AsyncStream` へ流す。
///
/// - Note: 読んだ内容を自分では持たない。持つと箱がスレッドを跨ぐため。
private final class OutputReader {

    /// 読んだバイト列が流れてくる列。
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
