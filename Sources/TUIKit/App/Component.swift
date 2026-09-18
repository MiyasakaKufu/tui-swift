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
    /// `body` が返すビューの型。適合側が `some View` で書けば推論される。
    associatedtype Body: View

    /// 現在の状態から画面を組み立てる。
    var body: Body { get }

    /// 入力イベントを処理する。
    func handle(_ event: InputEvent) -> EventResult

    /// 端末カーソルを表示したい位置。`nil` ならカーソルを隠す。
    var cursorPosition: Point? { get }

    /// 1 フレームごとに呼ばれる。`ApplicationOptions.frameInterval` を設定したときだけ定期的に呼ばれる。
    func update(elapsed: Double)
}

extension Component {
    /// 表示専用のアプリは入力を扱わなくてよい。
    ///
    /// すべてのイベントが未処理になるが、`ApplicationOptions.quitsOnControlC`
    /// が既定で有効なため Ctrl+C で終了できる。
    public func handle(_ event: InputEvent) -> EventResult { .ignored }

    public var cursorPosition: Point? { nil }

    public func update(elapsed: Double) {}
}
