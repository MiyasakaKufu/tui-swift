#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// イベントループへ渡すイベントを、スレッドをまたいで積むキュー。
///
/// 端末から届いたイベントと外部から送られたイベントを同じ列に積むため、取り出す順序は積んだ順になる。
final class EventQueue<Message: Sendable>: @unchecked Sendable {

    /// キューに積まれたイベント。
    enum Element {
        /// 端末から届いたイベント。
        case input(InputEvent)
        /// 外部から送られたイベント。
        case message(Message)
    }

    /// 外部から送られたイベントを積んでおける数の上限。
    let limit: Int

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private var elements: [Element] = []

    /// 上限を決めてキューを作る。
    ///
    /// - Parameters:
    ///   - limit: 外部から送られたイベントを積んでおける数の上限。
    init(limit: Int) {
        self.limit = limit
        // `pthread_mutex_t` を格納プロパティに置いて `&` で渡してはいけない。Swift は格納
        // プロパティの値を別の場所へ移してよいので、初期化したのと違う場所を指す
        // `pthread_mutex_lock` になりうる。
        mutex = UnsafeMutablePointer<pthread_mutex_t>.allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deinitialize(count: 1)
        mutex.deallocate()
    }

    /// 何も積まれていないか。
    var isEmpty: Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return elements.isEmpty
    }

    /// 外部から送られたイベントを積む。
    ///
    /// - Parameters:
    ///   - message: 積むイベント。
    /// - Returns: 積んだなら `true`。上限に達していて積まなかったなら `false`。
    func send(_ message: Message) -> Bool {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        guard elements.count < limit else { return false }
        elements.append(.message(message))
        return true
    }

    /// 端末から届いたイベントを積み、積まれているすべてのイベントを取り出す。
    ///
    /// - Parameters:
    ///   - inputEvents: 積む、端末から届いたイベント。
    /// - Returns: 積まれた順に並んだイベント。
    /// - Note: 端末から届いたイベントが上限を占めることはない。
    func drain(appending inputEvents: [InputEvent]) -> [Element] {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        elements.append(contentsOf: inputEvents.map { Element.input($0) })
        let drained = elements
        elements.removeAll()
        return drained
    }
}
