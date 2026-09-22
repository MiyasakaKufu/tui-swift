#if canImport(Synchronization)
import Synchronization

/// 計測用。`Mutex` で守った箱が `Sendable` を満たすかを見る。
@available(macOS 15, iOS 18, *)
final class ProbeQueue<Message: Sendable>: Sendable {

    private let storage = Mutex<[Message]>([])

    /// 値を積む。
    ///
    /// - Parameters:
    ///   - message: 積む値。
    func send(_ message: Message) {
        storage.withLock { $0.append(message) }
    }

    /// 積まれた値をすべて取り出す。
    ///
    /// - Returns: 積まれた順に並んだ値。
    func drain() -> [Message] {
        storage.withLock { values in
            let drained = values
            values.removeAll()
            return drained
        }
    }
}

/// `Sendable` を要求する関数。
///
/// - Parameters:
///   - value: 渡す値。
func probeRequiresSendable<T: Sendable>(_ value: T) {}

/// `ProbeQueue` を `Sendable` として渡してみる。
@available(macOS 15, iOS 18, *)
func probeMutexIsSendable() {
    probeRequiresSendable(ProbeQueue<Int>())
}
#endif
