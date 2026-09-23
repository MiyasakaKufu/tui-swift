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

    /// `MessageSender.send(_:)` で送る値の型。`receive(_:)` を書けば推論される。
    ///
    /// 既定は `Never`。`MessageSender` を使わないなら決めなくてよい。
    associatedtype Message: Sendable = Never

    /// 現在の状態から画面を組み立てる。
    var body: Body { get }

    /// 入力イベントを処理する。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: 処理の結果。`.quit` を返すとアプリケーションが終了する。
    func handle(_ event: InputEvent) -> EventResult

    /// 別スレッドや `Task` から `MessageSender.send(_:)` で送られた値を処理する。
    ///
    /// - Parameters:
    ///   - message: 送られた値。
    /// - Returns: 処理の結果。`.quit` を返すとアプリケーションが終了する。
    /// - Note: 送られた順に呼ばれる。`handle(_:)` との前後は、ライブラリが tty からキーを読んだ時点で決まる。
    ///   キーが tty に届いた時点ではないので、届いてから読むまでの間に送られた値は、そのキーより先に渡る。
    func receive(_ message: Message) -> EventResult

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

    /// `MessageSender` を使わないアプリは受け取らなくてよい。
    ///
    /// - Parameters:
    ///   - message: 送られた値。
    /// - Returns: 常に `.ignored`。
    public func receive(_ message: Message) -> EventResult { .ignored }

    /// カーソルを隠す。
    public var cursorPosition: Point? { nil }

    /// 何もしない。
    ///
    /// - Parameters:
    ///   - elapsed: 前のフレームからの経過秒数。
    public func update(elapsed: Double) {}
}
