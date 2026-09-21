// #106 の計測用。決定を記録したら消す。
//
// 各呼び出しが警告「does not conform to the 'Sendable' protocol」を出すかどうかで、
// その型が `Sendable` になっているかを見る。Swift 5 言語モードでは適合の不足が
// 警告にしかならないので、警告の有無がそのまま答えになる。

/// 引数が `Sendable` でなければ警告が出る受け口。
///
/// - Parameters:
///   - type: 判定する型。
func requireSendable<T: Sendable>(_ type: T.Type) {}

/// 隔離の対象になるグローバルアクタ。
@globalActor
actor ProbeActor {
    /// グローバルアクタの実体。
    static let shared = ProbeActor()
}

/// `Sendable` に適合しない参照型。
final class MutableBox {
    /// 書き換えられる状態。
    var value = 0
}

/// 隔離していない、`Sendable` でない状態を持つクラス。対照。
final class PlainHolder {
    /// `Sendable` でない状態。
    var box = MutableBox()
}

/// グローバルアクタに隔離した、`Sendable` でない状態を持つクラス。
@ProbeActor
final class IsolatedHolder {
    /// `Sendable` でない状態。
    var box = MutableBox()
}

/// グローバルアクタに隔離したプロトコル。
@ProbeActor
protocol IsolatedRenderable: AnyObject {
    /// 隔離の下でだけ呼べる処理。
    func render()
}

/// プロトコル単位の隔離だけを受けたクラス。
final class ProtocolIsolatedHolder: IsolatedRenderable {
    /// `Sendable` でない状態。
    var box = MutableBox()

    /// 何もしない。
    func render() {}
}

/// 隔離したプロトコルへ適合し、自身にも隔離を書いたクラス。
@ProbeActor
final class DoublyIsolatedHolder: IsolatedRenderable {
    /// `Sendable` でない状態。
    var box = MutableBox()

    /// 何もしない。
    func render() {}
}

/// 判定の呼び出しをまとめる。
func probe() {
    requireSendable(PlainHolder.self)             // 対照: 警告が出るはず
    requireSendable(IsolatedHolder.self)          // 型に隔離を書いた
    requireSendable(ProtocolIsolatedHolder.self)  // プロトコルの隔離だけ
    requireSendable(DoublyIsolatedHolder.self)    // 両方
    requireSendable(AsyncStream<Int>.Continuation.self)  // 外部との境界に使える値か
}
