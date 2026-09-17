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
///
/// 状態を持つため、値型ではなくクラスとして実装する。
public protocol Component: AnyObject {
    /// 現在の状態から画面を組み立てる。
    func body() -> any View

    /// 入力イベントを処理する。
    func handle(_ event: InputEvent) -> EventResult

    /// 端末カーソルを表示したい位置。`nil` ならカーソルを隠す。
    var cursorPosition: Point? { get }

    /// 1 フレームごとに呼ばれる。`Application.Options.frameInterval` を設定したときだけ定期的に呼ばれる。
    func update(elapsed: Double)
}

extension Component {
    public var cursorPosition: Point? { nil }
    public func update(elapsed: Double) {}
}
