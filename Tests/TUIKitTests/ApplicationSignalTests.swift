import XCTest
import Foundation
import CTUITestSupport
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// シグナルがイベントループへ届くかを、疑似端末（pty）の上で確かめる。
///
/// シグナルは `poll(2)` の最中ではなく、その直前に届くことがある。
/// 以前はフラグを立てるだけだったため、この場合は次の入力が来るまでループが動かなかった。
final class ApplicationSignalTests: XCTestCase {

    /// イベント待ちに入る直前の SIGWINCH でも、入力なしで再描画される。
    func testResizeJustBeforeWaitingTriggersRedraw() throws {
        let pty = try PseudoTerminal()
        defer { pty.close() }

        XCTAssertEqual(ctui_set_terminal_size(pty.master, 20, 5), 0, "初期サイズを設定できない")

        // 最初の描画の途中、つまりサイズを確認した後・イベント待ちに入る前にリサイズする。
        let probe = ResizeProbe {
            XCTAssertEqual(ctui_set_terminal_size(pty.master, 30, 8), 0, "サイズを変更できない")
            kill(getpid(), SIGWINCH)
        }

        let run = runInBackground(root: probe, terminal: pty.terminal())

        // 入力は一切送らない。修正前はここでタイムアウトする。
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

        XCTAssertEqual(ctui_set_terminal_size(pty.master, 20, 5), 0, "初期サイズを設定できない")

        let probe = TerminationProbe {
            kill(getpid(), SIGTERM)
        }

        let run = runInBackground(root: probe, terminal: pty.terminal())

        // 入力は一切送らない。修正前はここでタイムアウトする。
        wait(for: [run.finished], timeout: 5)

        XCTAssertNil(run.error.value)
    }

    /// 起こすための記述子が読めるようになれば、入力がなくても待ちが終わる。
    func testWaitReturnsWhenWakeupDescriptorBecomesReadable() throws {
        let input = try PipePair()
        defer { input.close() }
        let wakeup = try PipePair()
        defer { wakeup.close() }

        let reader = InputReader(descriptor: input.readEnd, wakeupDescriptor: wakeup.readEnd)
        wakeup.writeByte()

        // タイムアウトなしで待っても、合図があるので戻ってくる。
        XCTAssertTrue(reader.wait(timeout: nil).isEmpty)

        // 合図は読み捨てられているので、次の待ちがすぐ終わってしまうことはない。
        XCTAssertFalse(wakeup.isReadable, "合図が読み捨てられていない")
    }

    // MARK: - 補助

    /// 別スレッドでイベントループを回す。
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
/// 読み書きの順序は `XCTestExpectation` で保証する。
private final class ResultBox<Value>: @unchecked Sendable {
    var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// リサイズの通知を記録し、二度目で終了するコンポーネント。
///
/// 一度目は起動時のサイズ通知、二度目が SIGWINCH によるもの。
/// 最初の描画で一度だけ、渡された処理（リサイズとシグナル送信）を実行する。
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
        guard ctui_open_pty(&master, &slave) == 0 else {
            throw Failure.unavailable(errno: errno)
        }
        self.master = master
        self.slave = slave
    }

    deinit {
        close()
    }

    /// スレーブ側を入出力に使う端末。
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

/// `close(2)`。型のメソッド名と衝突しないよう、ファイルスコープの関数として定義している。
private func closeDescriptor(_ descriptor: Int32) {
    _ = close(descriptor)
}
