#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// ファイル記述子からイベントを読み出す。
public final class InputReader {
    private let descriptor: Int32
    private var parser = InputParser()
    private var readBuffer = [UInt8](repeating: 0, count: 4096)

    public init(descriptor: Int32 = 0) {
        self.descriptor = descriptor
    }

    /// 入力を待ち、届いたイベントを返す。
    ///
    /// - Parameter timeout: 待ち時間（秒）。`nil` ならイベントが届くまで待つ。
    /// - Returns: 解釈できたイベント。タイムアウト時は空配列。
    public func wait(timeout: Double?) -> [InputEvent] {
        let milliseconds: Int32
        if let timeout {
            milliseconds = Int32(max(0, min(Double(Int32.max), timeout * 1000)))
        } else {
            milliseconds = -1
        }

        let ready = waitForReadable(descriptor, milliseconds)
        if ready <= 0 {
            // タイムアウト（あるいはシグナルで中断）。途中まで届いた ESC はここで確定させる。
            return parser.flush()
        }

        var events: [InputEvent] = []
        while true {
            let count = readBuffer.withUnsafeMutableBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return read(descriptor, base, buffer.count)
            }
            if count > 0 {
                events.append(contentsOf: parser.feed(Array(readBuffer[0..<count])))
                if count < readBuffer.count { break }
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }

        if events.isEmpty && parser.hasPendingBytes {
            // 単独の ESC だけが届いた場合は、続きが来ないことを確認してから確定させる。
            if waitForReadable(descriptor, 20) <= 0 {
                events.append(contentsOf: parser.flush())
            }
        }
        return events
    }
}

/// `poll(2)` で読み取り可能になるまで待つ。
///
/// `InputReader` のメソッド名と衝突しないよう、ファイルスコープの関数として定義している。
private func waitForReadable(_ descriptor: Int32, _ timeoutMilliseconds: Int32) -> Int32 {
    var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
    let result = poll(&descriptors, 1, timeoutMilliseconds)
    return result
}
