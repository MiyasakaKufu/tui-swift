import XCTest

/// 型が `Sendable` に適合していないと選ばれる方。
///
/// - Parameters:
///   - type: 判定する型。
/// - Returns: 常に `false`。
private func conformsToSendable<T>(_ type: T.Type) -> Bool { false }

/// 型が `Sendable` に適合していると選ばれる方。
///
/// 制約の多い方が優先されるオーバーロード解決を使い、適合の有無を実行時の値へ落とす。
///
/// - Parameters:
///   - type: 判定する型。
/// - Returns: 常に `true`。
private func conformsToSendable<T: Sendable>(_ type: T.Type) -> Bool { true }

/// 隔離の対象になるグローバルアクタ。
@globalActor
private actor ProbeActor {
    /// グローバルアクタの実体。
    static let shared = ProbeActor()
}

/// `Sendable` に適合しない参照型。
private final class MutableBox {
    /// 書き換えられる状態。
    var value = 0
}

/// グローバルアクタに隔離した、`Sendable` でない状態を持つクラス。
@ProbeActor
private final class IsolatedHolder {
    /// `Sendable` でない状態。
    var box = MutableBox()
}

/// 隔離していない、`Sendable` でない状態を持つクラス。
private final class PlainHolder {
    /// `Sendable` でない状態。
    var box = MutableBox()
}

/// プロトコル自体をグローバルアクタに隔離した場合の適合先。
@ProbeActor
private protocol IsolatedRenderable: AnyObject {
    /// 隔離の下でだけ呼べる処理。
    func render()
}

/// プロトコル単位の隔離だけを受けたクラス。
private final class ProtocolIsolatedHolder: IsolatedRenderable {
    /// `Sendable` でない状態。
    var box = MutableBox()

    /// 何もしない。
    func render() {}
}

/// グローバルアクタへの隔離が `Sendable` 適合を与えるかを確かめる。
final class ConcurrencyIsolationProbeTests: XCTestCase {

    /// 判定そのものが働いていることを確かめる。
    func testProbeDistinguishesSendableConformance() {
        XCTAssertTrue(conformsToSendable(Int.self))
        XCTAssertFalse(conformsToSendable(PlainHolder.self))
    }

    /// グローバルアクタに隔離したクラスが、宣言を足さずに `Sendable` になることを確かめる。
    func testGlobalActorIsolatedClassIsSendable() {
        XCTAssertTrue(conformsToSendable(IsolatedHolder.self))
    }

    /// 隔離したプロトコルへの適合だけでも `Sendable` になることを確かめる。
    func testProtocolIsolationAloneMakesClassSendable() {
        XCTAssertTrue(conformsToSendable(ProtocolIsolatedHolder.self))
    }
}
