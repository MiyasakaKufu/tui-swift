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

    /// 応答を待つ間に届き、まだ返していないイベント。
    private var bufferedEvents: [InputEvent] = []

    /// 入力待ちを中断させるための記述子。
    ///
    /// `SignalWatcher.wakeupDescriptor` を渡すことを想定している。
    /// これが読み取り可能になると、`wait(timeout:)` は入力がなくても戻る。
    ///
    /// - Precondition: 読み取り可能になったバイトは読み捨てるため、非ブロッキングであること。
    public var wakeupDescriptor: Int32?

    /// 指定した記述子から読み出す `InputReader` を作る。
    ///
    /// - Parameters:
    ///   - descriptor: 入力を読み取るファイル記述子。
    ///   - wakeupDescriptor: 入力待ちを中断させる記述子。`nil` なら入力だけを待つ。
    public init(descriptor: Int32 = 0, wakeupDescriptor: Int32? = nil) {
        self.descriptor = descriptor
        self.wakeupDescriptor = wakeupDescriptor
    }

    /// 別の `InputReader` へ引き継ぐ、まだ返していない `InputEvent` と未解釈のバイト。
    struct UnreadState: Sendable {
        /// まだ返していないイベント。
        var events: [InputEvent]
        /// 未解釈のバイトを抱えたパーサ。
        var parser: InputParser
        /// 未解釈のバイトを最後に受け取った時刻。
        var pendingSince: Double?
    }

    /// まだ返していない `InputEvent` と未解釈のバイトを取り出し、この `InputReader` を空にする。
    ///
    /// - Returns: 取り出した分。引き継ぎ先で `adopt(_:)` へ渡す。
    func takeUnreadState() -> UnreadState {
        let state = UnreadState(events: bufferedEvents, parser: parser, pendingSince: pendingSince)
        bufferedEvents.removeAll()
        parser = InputParser()
        pendingSince = nil
        return state
    }

    /// 取り出した分を引き継ぐ。
    ///
    /// - Parameters:
    ///   - state: `takeUnreadState()` が返した分。
    /// - Precondition: まだ何も読んでいない `InputReader` であること。
    func adopt(_ state: UnreadState) {
        bufferedEvents = state.events
        parser = state.parser
        pendingSince = state.pendingSince
    }

    /// 入力を待ち、届いたイベントを返す。
    ///
    /// 途中までしか届いていない制御コードは、続きを待つ時間が過ぎるまで確定させない。
    /// 待ち時間は呼び出しをまたいで測るので、`timeout` より長くなることもある。
    ///
    /// `waitForQueryReplies(timeout:)` が待つ間に届いたイベントが残っていれば、待たずに返す。
    ///
    /// - Parameters:
    ///   - timeout: 待ち時間（秒）。`nil` ならイベントが届くまで待つ。
    /// - Returns: 解釈できたイベント。
    ///   タイムアウトしたときや、`wakeupDescriptor` で起こされたときは空配列。
    public func wait(timeout: Double?) -> [InputEvent] {
        if !bufferedEvents.isEmpty {
            let events = bufferedEvents
            bufferedEvents.removeAll()
            return events
        }

        let deadline = timeout.map { monotonicSeconds() + max(0, $0) }

        while true {
            let flushDeadline = pendingSince.flatMap { since in
                parser.pendingWaitDuration.map { since + $0 }
            }
            let readiness = waitForReadable(
                descriptor,
                wakeup: wakeupDescriptor,
                InputReader.milliseconds(until: earlier(deadline, flushDeadline))
            )

            if readiness.contains(.wakeup), let wakeup = wakeupDescriptor {
                discardPendingBytes(wakeup)
            }

            if readiness.contains(.input) {
                let (events, byteCount) = readAvailable()
                pendingSince = parser.hasPendingBytes ? monotonicSeconds() : nil
                // 閉じた記述子はいつでも読み取り可能になり、`read(2)` は 0 を返す。
                // 読めたバイト数を見ずに待ち直すと、入力が閉じた後は待ちの中で回り続ける。
                if !events.isEmpty || byteCount == 0 { return events }

                // 起こされた回に待ち直してはいけない。ペースト中は `pendingWaitDuration` が nil なので
                // 続きが届くまで戻らず、起こした側は戻ったつもりで待ち続ける。
                if readiness.contains(.wakeup) { return [] }
            } else if readiness.contains(.wakeup) {
                // 起こされただけのときに確定させてはいけない。届きかけの ESC が壊れる。
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

    /// 端末へ送った問い合わせの応答を、装置属性の応答が届くまで待つ。
    ///
    /// 装置属性（`CSI c`）の応答は、それより前に送った問い合わせの応答が出揃った目印になる。
    /// 呼ぶ前に、確かめたい問い合わせと続けて `ANSI.queryDeviceAttributes` も送っておく。
    ///
    /// - Parameters:
    ///   - timeout: 待ち時間（秒）。
    /// - Returns: 届いた応答。何も届かないまま時間切れになれば空配列。
    /// - Postcondition: 待つ間に届いたキーやマウスのイベントは捨てず、次の `wait(timeout:)` で返す。
    public func waitForQueryReplies(timeout: Double) -> [TerminalReply] {
        let deadline = monotonicSeconds() + max(0, timeout)
        var replies: [TerminalReply] = []

        while monotonicSeconds() < deadline {
            // ここでは読み捨てないので、渡すと `poll(2)` が即座に返り続け、時間切れまで空回りする。
            let readiness = waitForReadable(
                descriptor,
                wakeup: nil,
                InputReader.milliseconds(until: deadline)
            )
            guard readiness.contains(.input) else { continue }

            let (events, byteCount) = readAvailable()
            bufferedEvents.append(contentsOf: events)
            pendingSince = parser.hasPendingBytes ? monotonicSeconds() : nil
            replies.append(contentsOf: parser.takeReplies())

            // 閉じた記述子はいつでも読み取り可能になる。読めたバイト数を見ずに待ち直すと、
            // 入力が閉じた後は時間切れまで回り続ける。
            if byteCount == 0 { break }
            if replies.contains(.deviceAttributes) { break }
        }
        return replies
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
    wakeup wakeupDescriptor: Int32?,
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
