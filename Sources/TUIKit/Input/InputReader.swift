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

    /// 入力待ちを中断させるための記述子。`SignalWatcher.wakeupDescriptor` を想定している。
    ///
    /// ここが読み取り可能になると `wait(timeout:)` は入力がなくても戻る。
    /// 溜まったバイトは読み捨てるため、非ブロッキングな記述子であること。
    public var wakeupDescriptor: Int32?

    public init(descriptor: Int32 = 0, wakeupDescriptor: Int32? = nil) {
        self.descriptor = descriptor
        self.wakeupDescriptor = wakeupDescriptor
    }

    /// 入力を待ち、届いたイベントを返す。
    ///
    /// - Parameter timeout: 待ち時間（秒）。`nil` ならイベントが届くまで待つ。
    /// - Returns: 解釈できたイベント。タイムアウト時や、シグナルで起こされたときは空配列。
    public func wait(timeout: Double?) -> [InputEvent] {
        let milliseconds: Int32
        if let timeout {
            milliseconds = Int32(max(0, min(Double(Int32.max), timeout * 1000)))
        } else {
            milliseconds = -1
        }

        let readiness = waitForReadable(descriptor, wakeupDescriptor, milliseconds)

        if readiness.contains(.wakeup), let wakeup = wakeupDescriptor {
            discardPendingBytes(wakeup)
        }

        guard readiness.contains(.input) else {
            // シグナルで起こされただけなら、届きかけの ESC をここで確定させない。
            // 続きのバイトは次の待ちで受け取れる。
            if readiness.contains(.wakeup) { return [] }
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
            if !waitForReadable(descriptor, nil, 20).contains(.input) {
                events.append(contentsOf: parser.flush())
            }
        }
        return events
    }
}

/// `poll(2)` がどの記述子で起きたか。
private struct Readiness: OptionSet {
    let rawValue: Int

    /// 入力が読み取り可能になった。
    static let input = Readiness(rawValue: 1 << 0)
    /// シグナル通知のパイプが読み取り可能になった。
    static let wakeup = Readiness(rawValue: 1 << 1)
}

/// `poll(2)` で入力（と、あればシグナル通知）が読み取り可能になるまで待つ。
///
/// `InputReader` のメソッド名と衝突しないよう、ファイルスコープの関数として定義している。
private func waitForReadable(
    _ descriptor: Int32,
    _ wakeupDescriptor: Int32?,
    _ timeoutMilliseconds: Int32
) -> Readiness {
    var descriptors = [pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)]
    if let wakeupDescriptor {
        descriptors.append(pollfd(fd: wakeupDescriptor, events: Int16(POLLIN), revents: 0))
    }

    let result = descriptors.withUnsafeMutableBufferPointer { buffer -> Int32 in
        guard let base = buffer.baseAddress else { return -1 }
        return poll(base, nfds_t(buffer.count), timeoutMilliseconds)
    }
    guard result > 0 else { return [] }

    var readiness: Readiness = []
    if descriptors[0].revents != 0 { readiness.insert(.input) }
    if descriptors.count > 1, descriptors[1].revents != 0 { readiness.insert(.wakeup) }
    return readiness
}

/// 読み取り可能なバイトを読み捨てる。合図としてのパイプを空にするために使う。
private func discardPendingBytes(_ descriptor: Int32) {
    var scratch = [UInt8](repeating: 0, count: 64)
    while true {
        let count = scratch.withUnsafeMutableBufferPointer { buffer -> Int in
            guard let base = buffer.baseAddress else { return 0 }
            return read(descriptor, base, buffer.count)
        }
        if count > 0 {
            if count < scratch.count { break }
            continue
        }
        if count < 0 && errno == EINTR { continue }
        break
    }
}
