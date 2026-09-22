/// イベントループが実行し、結果を `Component.receive(_:)` へ届ける作業。
///
/// 値なので、実行と打ち切りはイベントループが持つ。
///
/// - Note: 作業が値を届けるたびに画面が描き直される。
///   `ApplicationOptions.frameInterval` を設定していなくても届く。
public struct Effect<Message: Sendable>: Sendable {

    private let makeTasks: @Sendable (MessageSender<Message>) -> [Task<Void, Never>]

    /// 作業を始める処理を指定して作る。
    ///
    /// - Parameters:
    ///   - makeTasks: 送り口を受け取って作業を始め、打ち切るための `Task` を返す処理。
    private init(makeTasks: @escaping @Sendable (MessageSender<Message>) -> [Task<Void, Never>]) {
        self.makeTasks = makeTasks
    }

    /// 何もしない作業。
    public static var none: Effect { Effect { _ in [] } }

    /// 非同期の処理を走らせ、返った値を届ける作業。
    ///
    /// - Parameters:
    ///   - work: 走らせる処理。返った値が `Component.receive(_:)` へ渡る。
    /// - Returns: 組み立てた作業。
    public static func run(_ work: @escaping @Sendable () async -> Message) -> Effect {
        Effect { sender in
            [Task.detached { sender.send(await work()) }]
        }
    }

    /// 値を何度でも届けられる処理を走らせる作業。
    ///
    /// 時計やファイル監視のように、終わりの決まっていない入力源を載せる。
    ///
    /// - Parameters:
    ///   - work: 走らせる処理。渡された関数を呼ぶたびに値が `Component.receive(_:)` へ渡る。
    /// - Returns: 組み立てた作業。
    /// - Note: 打ち切りは `Task.isCancelled` と、`Task.sleep` が投げるエラーで伝わる。
    ///   どちらも見ない処理は、ループが終わってもプロセスが終わるまで走り続ける。
    public static func stream(
        _ work: @escaping @Sendable (@escaping @Sendable (Message) -> Void) async -> Void
    ) -> Effect {
        Effect { sender in
            [Task.detached { await work { sender.send($0) } }]
        }
    }

    /// 複数の作業を同時に走らせる作業。
    ///
    /// - Parameters:
    ///   - effects: 同時に走らせる作業。
    /// - Returns: 組み立てた作業。
    public static func merge(_ effects: [Effect]) -> Effect {
        Effect { sender in effects.flatMap { $0.makeTasks(sender) } }
    }

    /// 作業を始める。
    ///
    /// - Parameters:
    ///   - sender: 届け先の送り口。
    /// - Returns: 打ち切るための `Task`。
    func start(sending sender: MessageSender<Message>) -> [Task<Void, Never>] {
        makeTasks(sender)
    }
}
