import Foundation
import XCTest
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// マウスイベントを受け取る範囲の切り替えを確かめる。
@MainActor
final class MouseTrackingTests: XCTestCase {

    /// `.buttons` では移動の報告（1003）を求めない。
    func testButtonTrackingDoesNotAskForMotionReports() async {
        XCTAssertFalse(ANSI.enableMouseTracking.contains("1003"))
        XCTAssertTrue(ANSI.enableMouseMotionTracking.contains("\u{1B}[?1003h"))
    }

    /// 通知を止めるときは移動の報告も止める。
    func testStoppingMouseTrackingAlsoStopsMotionReports() async {
        XCTAssertTrue(ANSI.disableMouseTracking.contains("\u{1B}[?1003l"))
        XCTAssertTrue(CrashRestorer.restoreSequence.contains(ANSI.disableMouseTracking))
    }

    /// 範囲ごとに対応するシーケンスを送り、同じ範囲を選び直しても送り直さない。
    func testTerminalSendsTheSequenceForEachRange() async throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.pipeUnavailable(errno: errno) }
        defer {
            _ = close(descriptors[0])
            _ = close(descriptors[1])
        }

        let terminal = Terminal(input: descriptors[0], output: descriptors[1])

        terminal.setMouseTracking(.buttons)
        XCTAssertEqual(readText(from: descriptors[0]), ANSI.enableMouseTracking)

        terminal.setMouseTracking(.buttons)
        var polled = pollfd(fd: descriptors[0], events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&polled, 1, 0), 0)

        terminal.setMouseTracking(.motion)
        XCTAssertEqual(
            readText(from: descriptors[0]),
            ANSI.disableMouseTracking + ANSI.enableMouseMotionTracking
        )
    }

    /// 範囲を狭めるときは、いったんすべて止めてから入れ直す。
    func testNarrowingTheRangeStopsMotionReports() async throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.pipeUnavailable(errno: errno) }
        defer {
            _ = close(descriptors[0])
            _ = close(descriptors[1])
        }

        let terminal = Terminal(input: descriptors[0], output: descriptors[1])
        terminal.setMouseTracking(.motion)
        _ = readText(from: descriptors[0])

        terminal.setMouseTracking(.buttons)
        XCTAssertEqual(
            readText(from: descriptors[0]),
            ANSI.disableMouseTracking + ANSI.enableMouseTracking
        )

        terminal.setMouseTracking(.disabled)
        XCTAssertEqual(readText(from: descriptors[0]), ANSI.disableMouseTracking)
    }
}

/// テストの前提が整わなかったときのエラー。
private enum Failure: Error {
    case pipeUnavailable(errno: Int32)
}

/// ファイル記述子から読めるだけ読み、UTF-8 の文字列にする。
///
/// - Parameters:
///   - descriptor: 読み取るファイル記述子。
///   - maximum: 読み取る最大バイト数。
/// - Returns: 読み取った文字列。読めなければ空文字列。
private func readText(from descriptor: Int32, maximum: Int = 256) -> String {
    var scratch = [UInt8](repeating: 0, count: maximum)
    let count = scratch.withUnsafeMutableBufferPointer { buffer -> Int in
        guard let base = buffer.baseAddress else { return 0 }
        return read(descriptor, base, buffer.count)
    }
    guard count > 0 else { return "" }
    return String(decoding: scratch[0..<count], as: UTF8.self)
}
