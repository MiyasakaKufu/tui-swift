/// `Component.handle(_:)` と `Component.receive(_:)` が返す、処理したかどうかと `Application` を終了するかを表す型。
public enum EventResult: Hashable, Sendable {
    /// 処理した。
    case handled
    /// 処理しなかった。
    case ignored
    /// `Application` を終了する。
    case quit
}

/// `Application` に `View` を返し、`InputEvent` と `Component.Message` を受け取る型が準拠するプロトコル。
@MainActor
public protocol Component: AnyObject {
    /// `Component.body` が返す `View` の型。準拠する型が `Component.body` を `some View` で書けば推論される。
    associatedtype Body: View

    /// `MessageSender.send(_:)` で送る値の型。`receive(_:)` を書けば推論される。
    ///
    /// 準拠する型が `Component.Message` を決めなければ `Never` になる。`MessageSender` を使わないなら決めなくてよい。
    associatedtype Message: Sendable = Never

    /// 現在の状態から画面を組み立てる。
    var body: Body { get }

    /// 入力イベントを処理する。
    ///
    /// - Parameters:
    ///   - event: `Application` が渡す `InputEvent`。
    /// - Returns: 処理したかどうかを表す `EventResult`。`.quit` を返すと `Application` が終了する。
    func handle(_ event: InputEvent) -> EventResult

    /// 別スレッドや `Task` から `MessageSender.send(_:)` で送られた値を処理する。
    ///
    /// - Parameters:
    ///   - message: 送られた値。
    /// - Returns: 処理したかどうかを表す `EventResult`。`.quit` を返すと `Application` が終了する。
    /// - Note: 送られた順に呼び出される。`Component.handle(_:)` との前後は、`InputReader` が端末デバイスから
    ///   キーのバイト列を読んだ時点で決まる。キーが端末デバイスに届いた時点ではないので、
    ///   届いてから読むまでの間に送られた値は、そのキーより先に渡る。
    func receive(_ message: Message) -> EventResult

    /// 端末エミュレータのカーソルを表示したい位置。`nil` ならカーソルを隠す。
    var cursorPosition: Point? { get }

    /// `Application.draw()` の直前に、前に呼び出されてからの経過秒数を受け取る。
    ///
    /// - Parameters:
    ///   - elapsed: 前に `Component.update(elapsed:)` を呼び出してからの経過秒数。
    ///     初回は `Application.run()` が最初の `.resize` を通知した時点から測り、一時停止していた時間は含めない。
    /// - Note: `InputEvent`・`Component.Message` を処理するたびに呼び出され、`ApplicationOptions.frameInterval` を
    ///   設定したときは、入力が無くてもその間隔で呼び出される。最初の `Application.draw()` の前には呼び出されない。
    func update(elapsed: Double)
}

extension Component {
    /// 表示専用の `Component` に準拠する型は入力を扱わなくてよい。
    ///
    /// - Parameters:
    ///   - event: `Application` が渡す `InputEvent`。
    /// - Returns: 常に `.ignored`。
    /// - Note: すべてのイベントが未処理になるが、イニシャライザの `quitsOnControlC:` 引数を省いて作った
    ///   `ApplicationOptions` では `ApplicationOptions.quitsOnControlC` が `true` なので、Ctrl+C で終了できる。
    public func handle(_ event: InputEvent) -> EventResult { .ignored }

    /// `MessageSender` を使わない `Component` に準拠する型は、`Component.Message` を受け取らなくてよい。
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
    ///   - elapsed: 前に `Component.update(elapsed:)` を呼び出してからの経過秒数。
    ///     初回は `Application.run()` が最初の `.resize` を通知した時点から測り、一時停止していた時間は含めない。
    public func update(elapsed: Double) {}
}
