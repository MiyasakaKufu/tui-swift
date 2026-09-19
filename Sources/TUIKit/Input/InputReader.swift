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

    /// 未解釈のバイトを最後に受け取った時刻。続きを待つ時間はここから測る。
    private var pendingSince: Double?

    /// 入力待ちを中断させるための記述子。
    ///
    /// `SignalWatcher.wakeupDescriptor` を渡すことを想定している。
    /// これが読み取り可能になると、`wait(timeout:)` は入力がなくても戻る。
    ///
    /// - Precondition: 読み取り可能になったバイトは読み捨てるため、非ブロッキングであること。
    public var wakeupDescriptor: Int32?

    /// 指定した記述子から読み出すリーダーを作る。
    ///
    /// - Parameters:
    ///   - descriptor: 入力を読み取るファイル記述子。
    ///   - wakeupDescriptor: 入力待ちを中断させる記述子。`nil` なら入力だけを待つ。
    public init(descriptor: Int32 = 0, wakeupDescriptor: Int32? = nil) {
        self.descriptor = descriptor
        self.wakeupDescriptor = wakeupDescriptor
    }

    /// 入力を待ち、届いたイベントを返す。
    ///
    /// 途中までしか届いていない制御コードは、続きを待つ時間が過ぎるまで確定させない。
    /// 待ち時間は呼び出しをまたいで測るので、`timeout` より長くなることもある。
    ///
    /// - Parameters:
    ///   - timeout: 待ち時間（秒）。`nil` ならイベントが届くまで待つ。
    /// - Returns: 解釈できたイベント。
    ///   タイムアウトしたときや、`wakeupDescriptor` で起こされたときは空配列。
    public func wait(timeout: Double?) -> [InputEvent] {
        let deadline = timeout.map { monotonicSeconds() + max(0, $0) }

        while true {
            let flushDeadline = pendingSince.flatMap { since in
                parser.pendingWaitDuration.map { since + $0 }
            }
            let readiness = waitForReadable(
                descriptor,
                wakeupDescriptor,
                InputReader.milliseconds(until: earlier(deadline, flushDeadline))
            )

            if readiness.contains(.wakeup), let wakeup = wakeupDescriptor {
                discardPendingBytes(wakeup)
            }

            if readiness.contains(.input) {
                let (events, byteCount) = readAvailable()
                pendingSince = parser.hasPendingBytes ? monotonicSeconds() : nil
                // 読むものがないのに読み取り可能なのは、入力が閉じたとき。待ち続けても届かない。
                if !events.isEmpty || byteCount == 0 { return events }
            } else if readiness.contains(.wakeup) {
                // 起こされただけのときに確定させてはいけない。届きかけの ESC が壊れる。
                // 続きのバイトは次の待ちで受け取る。
                return []
            } else {
                let now = monotonicSeconds()
                if let flushDeadline, now >= flushDeadline {
                    let events = parser.flush()
                    if !parser.hasPendingBytes { pendingSince = nil }
                    if !events.isEmpty { return events }
                }
                if let deadline, now >= deadline { return [] }
            }
        }
    }

    /// 読み取り可能なバイトをすべて読み、イベントと読めたバイト数を返す。
    ///
    /// - Returns: 解釈できたイベントと、読み取ったバイト数。
    private func readAvailable() -> (events: [InputEvent], byteCount: Int) {
        var events: [InputEvent] = []
        var byteCount = 0
        while true {
            let count = readBuffer.withUnsafeMutableBufferPointer { buffer -> Int in
                guard let base = buffer.baseAddress else { return 0 }
                return read(descriptor, base, buffer.count)
            }
            if count > 0 {
                byteCount += count
                events.append(contentsOf: parser.feed(Array(readBuffer[0..<count])))
                if count < readBuffer.count { break }
            } else if count < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
        return (events, byteCount)
    }

    /// 指定した時刻までの残り時間（ミリ秒）。
    ///
    /// - Parameters:
    ///   - deadline: 待ちを終える時刻。`nil` なら待ち続ける。
    /// - Returns: `poll(2)` に渡す待ち時間。`deadline` が `nil` なら負の値。
    private static func milliseconds(until deadline: Double?) -> Int32 {
        guard let deadline else { return -1 }
        let remaining = (deadline - monotonicSeconds()) * 1000
        return Int32(max(0, min(Double(Int32.max), remaining.rounded(.up))))
    }
}

/// 早いほうの時刻。片方が `nil` ならもう片方。
///
/// - Parameters:
///   - lhs: 比べる時刻。
///   - rhs: 比べる時刻。
/// - Returns: 早いほうの時刻。どちらも `nil` なら `nil`。
private func earlier(_ lhs: Double?, _ rhs: Double?) -> Double? {
    guard let lhs else { return rhs }
    guard let rhs else { return lhs }
    return min(lhs, rhs)
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
/// - Parameters:
///   - descriptor: 入力を読み取るファイル記述子。
///   - wakeupDescriptor: 入力待ちを中断させる記述子。`nil` なら入力だけを待つ。
///   - timeoutMilliseconds: 待ち時間（ミリ秒）。負なら読み取り可能になるまで待つ。
/// - Returns: 読み取り可能になった記述子の種別。タイムアウトや失敗では空。
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

/// 読み取り可能なバイトをすべて読み捨てる。
///
/// - Parameters:
///   - descriptor: 読み捨てる非ブロッキングなファイル記述子。
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
