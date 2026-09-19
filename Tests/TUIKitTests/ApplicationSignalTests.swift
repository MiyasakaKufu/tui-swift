import XCTest
import Dispatch
import Foundation
import CTUITestSupport
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// シグナルがイベントループへ届くかを、疑似端末（pty）の上で確かめる。
final class ApplicationSignalTests: XCTestCase {

    /// イベント待ちに入る直前の SIGWINCH でも、入力なしで再描画される。
    func testResizeJustBeforeWaitingTriggersRedraw() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }

        XCTAssertEqual(ctui_test_set_terminal_size(pty.master, 20, 5), 0, "初期サイズを設定できない")

        // `body` はサイズを確認した後・イベント待ちに入る前に呼ばれる。
        // ここでリサイズすることで、シグナルが届くタイミングを狙って揃えられる。
        let probe = ResizeProbe {
            XCTAssertEqual(ctui_test_set_terminal_size(pty.master, 30, 8), 0, "サイズを変更できない")
            kill(getpid(), SIGWINCH)
        }

        let run = runInBackground(root: probe, terminal: pty.terminal())

        // 入力を送ってはいけない。シグナルだけでループが動くことを確かめている。
        wait(for: [probe.resized, run.finished], timeout: 5)

        XCTAssertNil(run.error.value)
        XCTAssertEqual(
            probe.sizes,
            [Size(width: 20, height: 5), Size(width: 30, height: 8)]
        )
    }

    /// イベント待ちに入る直前の SIGTERM でも、入力なしでループが終わる。
    func testTerminationJustBeforeWaitingEndsLoop() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }

        XCTAssertEqual(ctui_test_set_terminal_size(pty.master, 20, 5), 0, "初期サイズを設定できない")

        let probe = TerminationProbe {
            kill(getpid(), SIGTERM)
        }

        let run = runInBackground(root: probe, terminal: pty.terminal())

        // 入力を送ってはいけない。シグナルだけでループが終わることを確かめている。
        wait(for: [run.finished], timeout: 5)

        XCTAssertNil(run.error.value)
    }

    /// 外から送られた SIGINT / SIGQUIT を終了シグナルとして受け取る。
    func testInterruptAndQuitAreTreatedAsTermination() throws {
        SignalWatcher.install()
        let descriptor = try XCTUnwrap(SignalWatcher.wakeupDescriptor)

        // 他のテストが残した合図を片付けてから確かめる。
        discard(descriptor)
        _ = SignalWatcher.consumeTermination()

        raise(SIGINT)

        XCTAssertTrue(SignalWatcher.consumeTermination(), "SIGINT が終了として扱われていない")
        XCTAssertTrue(isReadable(descriptor), "SIGINT でイベント待ちが起こされない")
        discard(descriptor)

        raise(SIGQUIT)

        XCTAssertTrue(SignalWatcher.consumeTermination(), "SIGQUIT が終了として扱われていない")
        XCTAssertTrue(isReadable(descriptor), "SIGQUIT でイベント待ちが起こされない")
        discard(descriptor)
    }

    /// 外から送られた SIGTSTP / SIGCONT を一時停止・再開として受け取る。
    func testSuspendAndContinueAreReported() throws {
        SignalWatcher.install()
        let descriptor = try XCTUnwrap(SignalWatcher.wakeupDescriptor)

        discard(descriptor)
        _ = SignalWatcher.consumeSuspend()
        _ = SignalWatcher.consumeContinue()

        // ハンドラを登録してあるので、プロセスは止まらずフラグが立つだけ。
        raise(SIGTSTP)

        XCTAssertTrue(SignalWatcher.consumeSuspend(), "SIGTSTP が一時停止として扱われていない")
        XCTAssertTrue(isReadable(descriptor), "SIGTSTP でイベント待ちが起こされない")
        discard(descriptor)

        raise(SIGCONT)

        XCTAssertTrue(SignalWatcher.consumeContinue(), "SIGCONT が再開として扱われていない")
        XCTAssertTrue(isReadable(descriptor), "SIGCONT でイベント待ちが起こされない")
        discard(descriptor)
    }

    /// シグナルハンドラが、起こすためのパイプへ書き込む。
    func testSignalWritesToWakeupDescriptor() throws {
        SignalWatcher.install()
        let descriptor = try XCTUnwrap(SignalWatcher.wakeupDescriptor)

        // 他のテストが残した合図を片付けてから確かめる。
        discard(descriptor)
        _ = SignalWatcher.consumeWindowResize()

        raise(SIGWINCH)

        XCTAssertTrue(isReadable(descriptor), "シグナルでパイプへ書き込まれていない")
        XCTAssertTrue(SignalWatcher.consumeWindowResize())

        discard(descriptor)
    }

    /// 起こすための記述子が読めるようになれば、入力がなくても待ちが終わる。
    func testWaitReturnsWhenWakeupDescriptorBecomesReadable() throws {
        let input = try PipePair()
        defer { input.close() }
        let wakeup = try PipePair()
        defer { wakeup.close() }

        let reader = InputReader(descriptor: input.readEnd, wakeupDescriptor: wakeup.readEnd)
        wakeup.writeByte()

        XCTAssertTrue(reader.wait(timeout: nil).isEmpty)
        XCTAssertFalse(wakeup.isReadable, "合図が読み捨てられていない")
    }

    // MARK: - 補助

    /// 別スレッドでイベントループを回す。
    ///
    /// - Parameters:
    ///   - root: ループに渡すコンポーネント。
    ///   - terminal: 入出力に使う端末。
    /// - Returns: ループの終了を待つための expectation と、`run()` が投げたエラーの入れ物。
    private func runInBackground<Root: Component>(
        root: Root,
        terminal: Terminal
    ) -> (finished: XCTestExpectation, error: ResultBox<Error?>) {
        let application = Application(
            root: root,
            options: ApplicationOptions(usesAlternateScreen: false, usesBracketedPaste: false),
            terminal: terminal
        )
        let finished = XCTestExpectation(description: "イベントループが終わる")
        let error = ResultBox<Error?>(nil)

        Thread.detachNewThread {
            do {
                try application.run()
            } catch let thrown {
                error.value = thrown
            }
            finished.fulfill()
        }

        return (finished, error)
    }
}

/// スレッドをまたいで結果を受け渡すための入れ物。
///
/// - Warning: 読み書きの順序は `XCTestExpectation` で揃える。
private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// リサイズの通知を記録し、二度目の通知で終了するコンポーネント。
///
/// 最初の描画で一度だけ、渡された処理を実行する。
private final class ResizeProbe: Component, @unchecked Sendable {
    private let trigger: () -> Void
    private var hasDrawn = false

    private(set) var sizes: [Size] = []
    let resized = XCTestExpectation(description: "新しいサイズが通知される")

    init(trigger: @escaping () -> Void) {
        self.trigger = trigger
    }

    var body: some View {
        if !hasDrawn {
            hasDrawn = true
            trigger()
        }
        return Text("リサイズ")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .resize(let size) = event else { return .ignored }
        sizes.append(size)
        guard sizes.count >= 2 else { return .handled }
        resized.fulfill()
        return .quit
    }
}

/// 最初の描画で一度だけ終了シグナルを送り、自分からは終了しないコンポーネント。
private final class TerminationProbe: Component, @unchecked Sendable {
    private let trigger: () -> Void
    private var hasDrawn = false

    init(trigger: @escaping () -> Void) {
        self.trigger = trigger
    }

    var body: some View {
        if !hasDrawn {
            hasDrawn = true
            trigger()
        }
        return Text("終了")
    }
}

/// テスト用の疑似端末。
///
/// マスタ側を読み続けるスレッドを持つ。
///
/// - Warning: 読み捨てをやめてはいけない。
///   出力バッファが詰まると、スレーブ側への `write(2)` や、出力の掃き出しを待つ
///   `tcsetattr(TCSAFLUSH)` が返らなくなる。
private final class PseudoTerminal {
    enum Failure: Error {
        case unavailable(errno: Int32)
    }

    let master: Int32
    let slave: Int32

    private var isClosed = false
    private let stopsDraining = AtomicFlag()
    private let drainingStopped = DispatchSemaphore(value: 0)

    init() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        guard ctui_test_open_pty(&master, &slave) == 0 else {
            throw Failure.unavailable(errno: errno)
        }
        self.master = master
        self.slave = slave
        startDraining()
    }

    deinit {
        close()
    }

    /// スレーブ側を入出力に使う端末を作る。
    func terminal() -> Terminal {
        Terminal(input: slave, output: slave)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        // 読み捨てスレッドが記述子を触らなくなってから閉じる。
        stopsDraining.set()
        drainingStopped.wait()
        closeDescriptor(slave)
        closeDescriptor(master)
    }

    private func startDraining() {
        let master = self.master
        let stopsDraining = self.stopsDraining
        let drainingStopped = self.drainingStopped

        Thread.detachNewThread {
            var scratch = [UInt8](repeating: 0, count: 4096)
            while !stopsDraining.isSet {
                var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptor, 1, 50) > 0 else { continue }

                let count = scratch.withUnsafeMutableBufferPointer { buffer -> Int in
                    guard let base = buffer.baseAddress else { return 0 }
                    return read(master, base, buffer.count)
                }
                if count > 0 { continue }
                if count < 0 && (errno == EINTR || errno == EAGAIN) { continue }
                break
            }
            drainingStopped.signal()
        }
    }
}

/// スレッドをまたいで使う真偽値。
private final class AtomicFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

/// テスト用のパイプ。
private final class PipePair {
    enum Failure: Error {
        case unavailable(errno: Int32)
    }

    let readEnd: Int32
    let writeEnd: Int32
    private var isClosed = false

    init() throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.unavailable(errno: errno) }
        readEnd = descriptors[0]
        writeEnd = descriptors[1]
    }

    deinit {
        close()
    }

    /// 読み取り側に未読のバイトがあるか。
    var isReadable: Bool {
        var descriptor = pollfd(fd: readEnd, events: Int16(POLLIN), revents: 0)
        return poll(&descriptor, 1, 0) > 0
    }

    func writeByte() {
        var byte: UInt8 = 0
        _ = write(writeEnd, &byte, 1)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        closeDescriptor(readEnd)
        closeDescriptor(writeEnd)
    }
}

// クラスの中から `close(2)` は直接呼べない。メンバーの `close()` が先に見つかる。
/// ファイル記述子を閉じる。
///
/// - Parameters:
///   - descriptor: 閉じるファイル記述子。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}

/// 未読のバイトがあるか。
///
/// - Parameters:
///   - descriptor: 調べるファイル記述子。
/// - Returns: 読み取り可能なら `true`。
private func isReadable(_ descriptor: Int32) -> Bool {
    var polled = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    return poll(&polled, 1, 0) > 0
}

/// 未読のバイトを読み捨てる。
///
/// - Parameters:
///   - descriptor: 読み捨てるファイル記述子。
/// - Precondition: `descriptor` は非ブロッキングであること。
private func discard(_ descriptor: Int32) {
    var scratch = [UInt8](repeating: 0, count: 64)
    while isReadable(descriptor) {
        let count = scratch.withUnsafeMutableBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return read(descriptor, base, buffer.count)
        }
        if count <= 0 { break }
    }
}
