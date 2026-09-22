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

    /// 起動時の作業が返した値で、`frameInterval` なしでも画面が更新される。
    func testStartupEffectResultUpdatesScreenWithoutFrameInterval() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent(startupEffect: .run { .arrived })
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        // 画面が変わるまで入力を送ってはいけない。作業の結果だけで変わることを確かめているので、
        // 入力で起きたのかどうかが分からなくなる。
        let drew = await waitUntil(timeout: 5) { self.captured.contains(arrivedText) }
        XCTAssertTrue(drew, "作業の結果が届いた後に画面が描き直されていない")

        writeByte(pty.master, UInt8(ascii: "q"))
        try await loop.value

        XCTAssertEqual(component.messages, [.arrived])
    }

    /// 終わりの決まっていない作業は、値を何度でも届けられる。
    func testStreamEffectDeliversManyMessages() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        let component = MessageRecordingComponent(
            quitsAfter: 3,
            startupEffect: .stream { send in
                for _ in 0..<3 {
                    send(.arrived)
                    try? await Task.sleep(nanoseconds: 1_000_000)
                }
            }
        )
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await loop.value

        XCTAssertEqual(component.messages, [.arrived, .arrived, .arrived])
    }

    /// ループが終わると、走っている作業が打ち切られる。
    func testStartupEffectIsCancelledWhenLoopEnds() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let reader = OutputReader(descriptor: pty.master)
        let capture = startCapturing(reader)
        defer { capture.cancel() }

        // 打ち切りの合図は `AsyncStream` で受ける。`Continuation` は `Sendable` なので、
        // 打ち切りに気付く側がアクタの外に居ても箱を `@unchecked Sendable` にしなくてよい。
        let (noticed, noticeContinuation) = AsyncStream<Void>.makeStream()
        let component = MessageRecordingComponent(
            quitsAfter: 1,
            startupEffect: .stream { send in
                send(.arrived)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                noticeContinuation.yield(())
                noticeContinuation.finish()
            }
        )
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let loop = Task { try await application.run() }

        try await loop.value

        var sawCancellation = false
        for await _ in noticed {
            sawCancellation = true
            break
        }
        XCTAssertTrue(sawCancellation, "ループが終わっても作業が打ち切られない")
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

        try await loop.value

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

        // raw モードへの切り替えは入力待ちのバイト列を捨てるため、最初の描画を待ってから送る。
        let drewBeforeSending = await waitUntil(timeout: 5) { component.hasDrawnOnce }
        XCTAssertTrue(drewBeforeSending, "最初の描画が終わらない")

        // 順序を入れ替えてはいけない。キーを先に書くと、ループがそれを読んだのと送ったのと
        // どちらが先か決まらず、確かめたい順序そのものが揺れる。
        sender.send(.first)
        writeByte(pty.master, UInt8(ascii: "a"))
        let gotBoth = await waitUntil(timeout: 5) { component.records.count >= 2 }
        XCTAssertTrue(gotBoth, "イベントとキーが届かない")

        // キーが届くのを待たずに送ってはいけない。キーより先に積まれて、逆向きを確かめられなくなる。
        writeByte(pty.master, UInt8(ascii: "b"))
        let gotSecondKey = await waitUntil(timeout: 5) { component.records.count >= 3 }
        XCTAssertTrue(gotSecondKey, "キーが届かない")
        sender.send(.second)

        try await loop.value

        XCTAssertEqual(component.records, ["message:first", "key:a", "key:b", "message:second"])
    }

    /// 上限に達した後の送信は捨てられる。
    func testSenderReportsFullQueue() async throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }

        let application = Application(
            root: MessageRecordingComponent(),
            options: ApplicationOptions(messageQueueLimit: 1),
            terminal: pty.terminal()
        )

        XCTAssertTrue(application.sender.send(.first))
        XCTAssertFalse(application.sender.send(.second), "上限を超えて積まれている")
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

    /// pty の出力を読み続け、`captured` へ足していく作業を始める。
    ///
    /// - Parameters:
    ///   - reader: 読み取り元。
    /// - Returns: 読み続ける作業。テストの終わりに打ち切る。
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
    /// - Note: `Thread.sleep` で待ってはいけない。アクタを止めるとイベントループが進まない。
    private func waitUntil(timeout: Double, condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return false }
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

    private let quitsAfter: Int
    private let effect: Effect<TestMessage>

    /// 受け取る件数と起動時の作業を決めて作る。
    ///
    /// - Parameters:
    ///   - quitsAfter: 記録がこの数に達したら終了する。`0` なら自分からは終了しない。
    ///   - startupEffect: 起動時にイベントループへ走らせる作業。
    init(quitsAfter: Int = 0, startupEffect: Effect<TestMessage> = .none) {
        self.quitsAfter = quitsAfter
        self.effect = startupEffect
    }

    var body: some View {
        hasDrawnOnce = true
        return Text(messages.isEmpty ? waitingText : arrivedText)
    }

    var startupEffect: Effect<TestMessage> { effect }

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

    /// slave 側を入出力に使う端末を作る。
    ///
    /// - Returns: slave 側につながった端末。
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

/// pty の master 側に溜まる出力を読み続け、読んだものを列へ流す。
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

/// 端末のサイズを設定する。
///
/// - Parameters:
///   - descriptor: 設定する端末のファイル記述子。
///   - size: 設定するサイズ。
/// - Returns: 成功なら `0`。
private func setTerminalSize(_ descriptor: Int32, _ size: Size) -> Int32 {
    ctui_test_set_terminal_size(descriptor, Int32(size.width), Int32(size.height))
}

/// 端末へ 1 バイト書く。
///
/// - Parameters:
///   - descriptor: 書き込む先のファイル記述子。
///   - byte: 書き込むバイト。
private func writeByte(_ descriptor: Int32, _ byte: UInt8) {
    var value = byte
    _ = write(descriptor, &value, 1)
}
