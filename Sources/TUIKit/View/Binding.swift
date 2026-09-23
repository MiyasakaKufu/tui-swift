/// 別の場所にある値を読み書きする口。
///
/// ウィジェットに値そのものを持たせず、アプリが持つ値を編集させるときに渡す。
/// 読み出しと書き戻しの組を持つだけの値型で、値の持ち主は作った側に残る。
///
/// - Note: `TextField` と `ListView` が書き戻すのは、状態の `handle(_:)` などの操作の中だけで、
///   描画（`sizeThatFits(_:context:)` と `render(into:rect:context:)`）では読み出すだけ。
///   自作のビューも、描画の中で `wrappedValue` へ代入しない。
@MainActor
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    /// 読み出しと書き戻しを指定して口を作る。
    ///
    /// - Parameters:
    ///   - get: 現在の値を返す。
    ///   - set: 新しい値を持ち主へ書き戻す。
    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    /// オブジェクトのプロパティを読み書きする口を作る。
    ///
    /// - Parameters:
    ///   - root: 値を持つオブジェクト。
    ///   - keyPath: 読み書きするプロパティ。
    /// - Note: `root` を強く参照する。`TextField(text:state:)` や `ListView(items:selection:state:)` に
    ///   渡した口は状態が持ち続けるので、`root` がその状態を持っていれば、どちらも解放されない。
    public init<Root: AnyObject>(_ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>) {
        self.init(
            get: { root[keyPath: keyPath] },
            set: { root[keyPath: keyPath] = $0 }
        )
    }

    /// 常に同じ値を返し、書き戻しを捨てる口を作る。
    ///
    /// - Parameters:
    ///   - value: 返す値。
    /// - Returns: `value` を返し続ける口。
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// 持ち主の現在の値。代入すると持ち主へ書き戻す。
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }
}
