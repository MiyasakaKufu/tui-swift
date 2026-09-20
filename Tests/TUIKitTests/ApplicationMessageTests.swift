#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Dispatch
import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// 外部から届いたイベントがイベントループへ渡るかを、疑似端末（pty）の上で確かめる。
final class ApplicationMessageTests: XCTestCase {

    /// 起動時の作業が返した値で、`frameInterval` なしでも画面が更新される。
    func testStartupEffectResultUpdatesScreenWithoutFrameInterval() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let drain = OutputDrain(descriptor: pty.master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let component = MessageRecordingComponent(startupEffect: .run { .arrived })
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())

        let finished = expectation(description: "イベントループが終わる")
        let error = ErrorBox()
        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        // 画面が変わるまで入力を送ってはいけない。作業の結果だけで変わることを確かめているので、
        // 入力で起きたのかどうかが分からなくなる。
        XCTAssertTrue(
            drain.waitForOutput(containing: arrivedText, timeout: 5),
            "作業の結果が届いた後に画面が描き直されていない"
        )

        writeByte(pty.master, UInt8(ascii: "q"))
        wait(for: [finished], timeout: 5)

        XCTAssertNil(error.value)
        XCTAssertEqual(component.messages, [.arrived])
    }

    /// 終わりの決まっていない作業は、値を何度でも届けられる。
    func testStreamEffectDeliversManyMessages() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let drain = OutputDrain(descriptor: pty.master)
        drain.start()
        defer { drain.stop() }

        let expectedCount = 3
        let component = MessageRecordingComponent(
            quitsAfter: expectedCount,
            startupEffect: .stream { send in
                for _ in 0..<expectedCount { send(.arrived) }
            }
        )
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())

        let finished = expectation(description: "イベントループが終わる")
        let error = ErrorBox()
        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 10)

        XCTAssertNil(error.value)
        XCTAssertEqual(component.messages, Array(repeating: TestMessage.arrived, count: expectedCount))
    }

    /// ループが終わると、走っている作業が打ち切られる。
    func testStartupEffectIsCancelledWhenLoopEnds() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let drain = OutputDrain(descriptor: pty.master)
        drain.start()
        defer { drain.stop() }

        let noticedCancellation = Latch()
        let component = MessageRecordingComponent(
            quitsAfter: 1,
            startupEffect: .stream { send in
                send(.arrived)
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 5_000_000)
                }
                noticedCancellation.set()
            }
        )
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())

        let finished = expectation(description: "イベントループが終わる")
        let error = ErrorBox()
        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        wait(for: [finished], timeout: 10)

        XCTAssertNil(error.value)
        XCTAssertTrue(noticedCancellation.wait(timeout: 5), "ループが終わっても作業が打ち切られない")
    }

    /// 複数のスレッドから同時に送っても、すべてのイベントが届く。
    func testMessagesFromManyThreadsAllArrive() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let drain = OutputDrain(descriptor: pty.master)
        drain.start()
        defer { drain.stop() }

        let threadCount = 4
        let countPerThread = 50
        let component = MessageRecordingComponent(quitsAfter: threadCount * countPerThread)
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let sender = application.sender

        let finished = expectation(description: "イベントループが終わる")
        let error = ErrorBox()
        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        for _ in 0..<threadCount {
            Thread.detachNewThread {
                for _ in 0..<countPerThread { sender.send(.arrived) }
            }
        }

        wait(for: [finished], timeout: 10)

        XCTAssertNil(error.value)
        XCTAssertEqual(component.records.count, threadCount * countPerThread)
    }

    /// キー入力と外部イベントが、積まれた順のまま届く。
    func testInputAndMessagesKeepOrder() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }
        XCTAssertEqual(setTerminalSize(pty.master, Size(width: 40, height: 6)), 0)

        let drain = OutputDrain(descriptor: pty.master)
        drain.start()
        defer { drain.stop() }

        let component = MessageRecordingComponent(quitsAfter: 4)
        let application = Application(root: component, options: testOptions, terminal: pty.terminal())
        let sender = application.sender

        let finished = expectation(description: "イベントループが終わる")
        let error = ErrorBox()
        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        // raw モードへの切り替えは入力待ちのバイト列を捨てるため、最初の描画を待ってから送る。
        XCTAssertTrue(component.hasDrawnOnce.wait(timeout: 5), "最初の描画が終わらない")

        // 順序を入れ替えてはいけない。キーを先に書くと、ループがそれを読んだのと送ったのと
        // どちらが先か決まらず、確かめたい順序そのものが揺れる。
        sender.send(.first)
        writeByte(pty.master, UInt8(ascii: "a"))
        XCTAssertTrue(component.awaitRecordCount(2, timeout: 5), "イベントとキーが届かない")

        // キーが届くのを待たずに送ってはいけない。キーより先に積まれて、逆向きを確かめられなくなる。
        writeByte(pty.master, UInt8(ascii: "b"))
        XCTAssertTrue(component.awaitRecordCount(3, timeout: 5), "キーが届かない")
        sender.send(.second)

        wait(for: [finished], timeout: 5)

        XCTAssertNil(error.value)
        XCTAssertEqual(component.records, ["message:first", "key:a", "key:b", "message:second"])
    }

    /// 上限に達した後の送信は捨てられ、取り出した後はまた積める。
    func testQueueRejectsMessagesBeyondLimit() {
        let queue = EventQueue<Int>(limit: 2)

        XCTAssertTrue(queue.send(1))
        XCTAssertTrue(queue.send(2))
        XCTAssertFalse(queue.send(3), "上限を超えて積まれている")

        XCTAssertEqual(describe(queue.drain(appending: [.focus(true)])), ["1", "2", "focus(true)"])
        XCTAssertTrue(queue.send(4), "取り出した後に積めていない")
        XCTAssertEqual(describe(queue.drain(appending: [])), ["4"])
    }

    /// 上限は `Application.send(_:)` にも効く。
    func testApplicationSendReportsFullQueue() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }

        let application = Application(
            root: MessageRecordingComponent(),
            options: ApplicationOptions(messageQueueLimit: 1),
            terminal: pty.terminal()
        )

        XCTAssertTrue(application.send(.first))
        XCTAssertFalse(application.send(.second), "上限を超えて積まれている")
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

    /// 取り出したイベントを、比較できる文字列に直す。
    ///
    /// - Parameters:
    ///   - elements: 取り出したイベント。
    /// - Returns: 1 件に 1 つの文字列。
    private func describe(_ elements: [EventQueue<Int>.Element]) -> [String] {
        elements.map { element in
            switch element {
            case .input(let event): return String(describing: event)
            case .message(let message): return String(message)
            }
        }
    }
}

/// スレッドをまたいでエラーを受け渡すための入れ物。
///
/// - Warning: 読み書きの順序は `XCTestExpectation` で揃える。
private final class ErrorBox: @unchecked Sendable {
    var value: Error?
}

/// 一度立つと戻らないフラグ。
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var isRaised = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRaised
    }

    func set() {
        lock.lock()
        isRaised = true
        lock.unlock()
    }

    /// フラグが立つまで待つ。
    ///
    /// - Parameters:
    ///   - timeout: 待つ秒数の上限。
    /// - Returns: 時間内に立てば `true`。
    func wait(timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isSet {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
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
private final class MessageRecordingComponent: Component, @unchecked Sendable {

    /// 受け取ったイベントを届いた順に並べたもの。
    private(set) var messages: [TestMessage] = []
    /// 最初の描画が終わったら立つ。
    let hasDrawnOnce = Latch()

    private let quitsAfter: Int
    private let effect: Effect<TestMessage>
    private let lock = NSLock()
    private var entries: [String] = []

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
        hasDrawnOnce.set()
        return Text(messages.isEmpty ? waitingText : arrivedText)
    }

    var startupEffect: Effect<TestMessage> { effect }

    /// 受け取ったイベントとキーを、届いた順に文字列で並べたもの。
    var records: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
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

    /// 記録が決めた数に達するまで待つ。
    ///
    /// - Parameters:
    ///   - count: 待つ記録の数。
    ///   - timeout: 待つ秒数の上限。
    /// - Returns: 時間内に達すれば `true`。
    func awaitRecordCount(_ count: Int, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while records.count < count {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    /// 届いたものを記録し、終了するかを決める。
    ///
    /// - Parameters:
    ///   - entry: 記録する文字列。
    /// - Returns: 決めた数に達したなら `.quit`、まだなら `.handled`。
    private func record(_ entry: String) -> EventResult {
        lock.lock()
        entries.append(entry)
        let count = entries.count
        lock.unlock()
        return count == quitsAfter ? .quit : .handled
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
/// - Warning: master 側は `OutputDrain` で読み続ける。出力バッファが詰まると、
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

/// pty の master 側に溜まる出力を読み続けるスレッド。
///
/// 求められたときだけ読んだ内容を覚え、それ以外は読み捨てる。
private final class OutputDrain: @unchecked Sendable {
    private let descriptor: Int32
    private let recordsOutput: Bool
    private let lock = NSLock()
    private let stopped = DispatchSemaphore(value: 0)
    private var isStopped = false
    private var recorded: [UInt8] = []

    /// 読み続ける記述子を決めて作る。
    ///
    /// - Parameters:
    ///   - descriptor: 読み続けるファイル記述子。
    ///   - recordsOutput: 読んだ内容を覚えるか。
    init(descriptor: Int32, recordsOutput: Bool = false) {
        self.descriptor = descriptor
        self.recordsOutput = recordsOutput
    }

    func start() {
        Thread.detachNewThread {
            var bytes = [UInt8](repeating: 0, count: 4096)
            while self.isRunning {
                var polled = pollfd(fd: self.descriptor, events: Int16(POLLIN), revents: 0)
                guard poll(&polled, 1, 50) > 0 else { continue }
                let count = read(self.descriptor, &bytes, bytes.count)
                if count <= 0 { break }
                self.record(bytes[0..<count])
            }
            self.stopped.signal()
        }
    }

    func stop() {
        lock.lock()
        isStopped = true
        lock.unlock()
        // 待たずに戻ってはいけない。読み続けるスレッドが残った状態で記述子を閉じると、
        // 同じ番号を受け取った別の記述子から読み始める。
        stopped.wait()
    }

    /// 読んだ内容に部分列が現れるまで待つ。
    ///
    /// - Parameters:
    ///   - sequence: 探す部分列。
    ///   - timeout: 待つ秒数の上限。
    /// - Returns: 時間内に現れれば `true`。
    func waitForOutput(containing sequence: String, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while output.range(of: sequence) == nil {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !isStopped
    }

    private var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: recorded, as: UTF8.self)
    }

    private func record(_ bytes: ArraySlice<UInt8>) {
        guard recordsOutput else { return }
        lock.lock()
        recorded.append(contentsOf: bytes)
        lock.unlock()
    }
}

private func setTerminalSize(_ descriptor: Int32, _ size: Size) -> Int32 {
    ctui_test_set_terminal_size(descriptor, Int32(size.width), Int32(size.height))
}

private func writeByte(_ descriptor: Int32, _ byte: UInt8) {
    var value = byte
    _ = write(descriptor, &value, 1)
}

// クラスの中から `close(2)` は直接呼べない。メンバーの `close()` が先に見つかる。
/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}
