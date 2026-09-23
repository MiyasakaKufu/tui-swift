import Synchronization

/// `Synchronization` の `Mutex` で状態を守り、`@unchecked` なしで `Sendable` にした計数器。
///
/// Linux の Swift 6.0 で `Mutex` が使えるかを確かめる spike。本体からは使わない。
final class MutexSpikeCounter: Sendable {

    private let state = Mutex<[Int]>([])

    /// 値を末尾に足す。
    ///
    /// - Parameters:
    ///   - value: 足す値。
    func append(_ value: Int) {
        state.withLock { $0.append(value) }
    }

    /// 溜まっている値をすべて取り出し、空に戻す。
    ///
    /// - Returns: 取り出した値。
    func takeAll() -> [Int] {
        state.withLock { values in
            let taken = values
            values = []
            return taken
        }
    }
}
