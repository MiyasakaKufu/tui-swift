import Foundation
import XCTest
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 制御コードが途中で分かれて届いたときの `InputReader` の振る舞いを確かめる。
final class InputReaderTests: XCTestCase {

    /// 途中までの制御コードは確定させず、続きが届いてから 1 つのイベントにする。
    func testSequenceDelayedMidwayIsNotTurnedIntoEscape() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("\u{1B}[<65;10")
        XCTAssertEqual(reader.wait(timeout: 0.1), [])

        input.send(";5M")
        XCTAssertEqual(reader.wait(timeout: 1), [
            .mouse(MouseEvent(position: Point(x: 9, y: 4), button: .none, action: .scrollDown))
        ])
    }

    /// 起こされただけのときも、途中までの制御コードは確定させない。
    func testWakeupDoesNotFinishHalfSequence() throws {
        let input = try PipePair()
        defer { input.close() }
        let wakeup = try PipePair()
        defer { wakeup.close() }
        let reader = InputReader(descriptor: input.readEnd, wakeupDescriptor: wakeup.readEnd)

        input.send("\u{1B}[<65;10")
        XCTAssertEqual(reader.wait(timeout: 0.1), [])

        wakeup.send("\u{0}")
        XCTAssertEqual(reader.wait(timeout: 0.1), [])

        input.send(";5M")
        XCTAssertEqual(reader.wait(timeout: 1), [
            .mouse(MouseEvent(position: Point(x: 9, y: 4), button: .none, action: .scrollDown))
        ])
    }

    /// 単独で届いた ESC は Escape キーになる。
    func testLoneEscapeBecomesEscapeKey() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("\u{1B}")
        XCTAssertEqual(reader.wait(timeout: 1), [.key(KeyEvent(.escape))])
    }

    /// `ESC [` だけが届いたまま時間が過ぎれば Alt+[ になる。
    func testLoneBracketBecomesAltBracket() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("\u{1B}[")
        XCTAssertEqual(
            reader.wait(timeout: 5),
            [.key(KeyEvent(.character("["), modifiers: .alt))]
        )
    }

    /// 続きが届かなかった制御コードは、文字のキーに分解されない。
    func testTimedOutHalfSequenceProducesNoKeys() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("\u{1B}[<65;10")
        XCTAssertEqual(reader.wait(timeout: 5), [])
    }

    /// 装置属性の応答が届いた時点で、待ち時間を使い切らずに戻る。
    func testQueryRepliesReturnOnceDeviceAttributesArrive() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("\u{1B}[?1u\u{1B}[?62;c")
        let started = Date()
        XCTAssertEqual(
            reader.waitForQueryReplies(timeout: 5),
            [.keyboardProtocol(flags: 1), .deviceAttributes]
        )
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }

    /// 応答しない端末では、待ち時間が過ぎたら応答なしとして戻る。
    func testQueryRepliesGiveUpAfterTimeout() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        XCTAssertEqual(reader.waitForQueryReplies(timeout: 0.1), [])
    }

    /// 応答を待つ間に届いたキーは捨てず、次の待ちで返す。
    func testKeysArrivingWhileWaitingForRepliesAreKept() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.send("a\u{1B}[?1u\u{1B}[?62;c")
        XCTAssertEqual(
            reader.waitForQueryReplies(timeout: 5),
            [.keyboardProtocol(flags: 1), .deviceAttributes]
        )
        XCTAssertEqual(reader.wait(timeout: 0.1), [.key(KeyEvent(.character("a")))])
    }

    /// 入力が閉じていれば、待ち時間を使い切らずに戻る。
    func testClosedInputReturnsWithoutWaiting() throws {
        let input = try PipePair()
        defer { input.close() }
        let reader = InputReader(descriptor: input.readEnd)

        input.closeWriteEnd()
        let started = Date()
        XCTAssertEqual(reader.wait(timeout: 5), [])
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
    }
}

/// テスト用のパイプ。
private final class PipePair {

    /// パイプを作れなかった。
    enum Failure: Error {

        /// `pipe(2)` が失敗した。
        case unavailable(errno: Int32)
    }

    /// 読み取り側の記述子。
    let readEnd: Int32
    /// 書き込み側の記述子。
    let writeEnd: Int32
    private var isReadEndClosed = false
    private var isWriteEndClosed = false

    /// つながった読み書き 1 組を作る。
    ///
    /// - Throws: パイプを作れなければ `Failure.unavailable`。
    init() throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.unavailable(errno: errno) }
        readEnd = descriptors[0]
        writeEnd = descriptors[1]
    }

    deinit {
        close()
    }

    /// 文字列を書き込み側へ流す。
    ///
    /// - Parameters:
    ///   - text: 流す文字列。
    func send(_ text: String) {
        var bytes = Array(text.utf8)
        _ = write(writeEnd, &bytes, bytes.count)
    }

    /// 書き込み側だけを閉じ、読み取り側から見て入力が終わった状態にする。
    func closeWriteEnd() {
        guard !isWriteEndClosed else { return }
        isWriteEndClosed = true
        closeDescriptor(writeEnd)
    }

    /// 両方の記述子を閉じる。
    func close() {
        closeWriteEnd()
        guard !isReadEndClosed else { return }
        isReadEndClosed = true
        closeDescriptor(readEnd)
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
