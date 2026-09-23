import XCTest
@testable import TUIKit

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@MainActor
final class ClipboardTests: XCTestCase {

    func testSequenceCarriesTheTextAsBase64() async {
        XCTAssertEqual(ANSI.setClipboard("hi"), "\u{1B}]52;c;aGk=\u{07}")
        XCTAssertEqual(ANSI.setClipboard("あ"), "\u{1B}]52;c;44GC\u{07}")
    }

    func testEmptyTextClearsTheClipboard() async {
        XCTAssertEqual(ANSI.setClipboard(""), "\u{1B}]52;c;\u{07}")
    }

    func testSequenceHasNoControlCharactersBesidesItsOwn() async throws {
        let sequence = try XCTUnwrap(ANSI.setClipboard("\u{1B}[2J\u{07}\n改行"))
        let body = sequence.dropFirst(2).dropLast()
        XCTAssertFalse(body.unicodeScalars.contains { $0.value < 0x20 })
    }

    func testTextAtTheLimitIsStillSent() async {
        XCTAssertEqual(ANSI.setClipboard("abc", limit: 4), "\u{1B}]52;c;YWJj\u{07}")
    }

    func testTextOverTheLimitIsRefused() async {
        XCTAssertNil(ANSI.setClipboard("abcd", limit: 4))
        XCTAssertNil(ANSI.setClipboard("", limit: -1))
    }

    func testLimitCountsTheEncodedLength() async {
        XCTAssertNil(ANSI.setClipboard("あ", limit: 3))
        XCTAssertNotNil(ANSI.setClipboard("あ", limit: 4))
    }

    func testDefaultLimitAcceptsTextUpToItsLength() async {
        let bytes = ANSI.clipboardLimit / 4 * 3
        XCTAssertNotNil(ANSI.setClipboard(String(repeating: "a", count: bytes)))
        XCTAssertNil(ANSI.setClipboard(String(repeating: "a", count: bytes + 1)))
    }

    func testTerminalSendsTheSequenceImmediately() async throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.pipeUnavailable(errno: errno) }
        defer {
            _ = close(descriptors[0])
            _ = close(descriptors[1])
        }

        let terminal = Terminal(input: descriptors[0], output: descriptors[1])
        XCTAssertTrue(terminal.copyToClipboard("hi"))
        XCTAssertEqual(readText(from: descriptors[0]), "\u{1B}]52;c;aGk=\u{07}")
    }

    func testTerminalSendsNothingOverTheLimit() async throws {
        var descriptors: [Int32] = [-1, -1]
        guard pipe(&descriptors) == 0 else { throw Failure.pipeUnavailable(errno: errno) }
        defer {
            _ = close(descriptors[0])
            _ = close(descriptors[1])
        }

        let terminal = Terminal(input: descriptors[0], output: descriptors[1])
        XCTAssertFalse(terminal.copyToClipboard("abcd", limit: 4))

        var polled = pollfd(fd: descriptors[0], events: Int16(POLLIN), revents: 0)
        XCTAssertEqual(poll(&polled, 1, 0), 0)
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
