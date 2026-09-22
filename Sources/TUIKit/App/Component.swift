/// イベント処理の結果。
public enum EventResult: Hashable, Sendable {
    /// 処理した。
    case handled
    /// 処理しなかった。
    case ignored
    /// アプリケーションを終了する。
    case quit
}

/// アプリケーションのルートになるもの。
@MainActor
public protocol Component: AnyObject {
    /// `body` が返すビューの型。適合側が `some View` で書けば推論される。
    associatedtype Body: View

    /// 外部から送るイベントの型。`receive(_:)` を書けば推論される。
    ///
    /// 既定は `Never`。外部からイベントを送らないなら決めなくてよい。
    associatedtype Message: Sendable = Never

    /// 現在の状態から画面を組み立てる。
    var body: Body { get }

    /// 入力イベントを処理する。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: 処理の結果。`.quit` を返すとアプリケーションが終了する。
    func handle(_ event: InputEvent) -> EventResult

    /// 外部から送られたイベントを処理する。
    ///
    /// - Parameters:
    ///   - message: `MessageSender.send(_:)` で送られたイベント。
    /// - Returns: 処理の結果。`.quit` を返すとアプリケーションが終了する。
    /// - Note: 送られた順に呼ばれる。端末の入力との前後も保たれる。
    func receive(_ message: Message) -> EventResult

    /// 起動時にイベントループが走らせる作業。
    ///
    /// 通信やファイル読み込みのように、待つあいだ画面を止めたくない処理をここで組み立てる。
    /// 実行するのはイベントループで、結果は `receive(_:)` へ渡る。
    ///
    /// - Note: ループが終わるときに打ち切られる。
    var startupEffect: Effect<Message> { get }

    /// 端末カーソルを表示したい位置。`nil` ならカーソルを隠す。
    var cursorPosition: Point? { get }

    /// 1 フレームごとに呼ばれる。
    ///
    /// - Parameters:
    ///   - elapsed: 前のフレームからの経過秒数。
    /// - Note: `ApplicationOptions.frameInterval` を設定したときだけ定期的に呼ばれる。
    func update(elapsed: Double)
}

extension Component {
    /// 表示専用のアプリは入力を扱わなくてよい。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: 常に `.ignored`。
    /// - Note: すべてのイベントが未処理になるが、`ApplicationOptions.quitsOnControlC`
    ///   が既定で有効なため Ctrl+C で終了できる。
    public func handle(_ event: InputEvent) -> EventResult { .ignored }

    /// 外部からイベントを送らないアプリは受け取らなくてよい。
    ///
    /// - Parameters:
    ///   - message: 送られたイベント。
    /// - Returns: 常に `.ignored`。
    public func receive(_ message: Message) -> EventResult { .ignored }

    /// 起動時に何も走らせない。
    public var startupEffect: Effect<Message> { .none }

    /// カーソルを隠す。
    public var cursorPosition: Point? { nil }

    /// 何もしない。
    ///
    /// - Parameters:
    ///   - elapsed: 前のフレームからの経過秒数。
    public func update(elapsed: Double) {}
}
