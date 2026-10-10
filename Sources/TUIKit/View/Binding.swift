/// 別の場所にあるプロパティの値を取得し、書き換える型。
///
/// `TextField` の `text:` 引数や `ListView` の `selection:` 引数に渡すと、`TextFieldState`・`ListState` が、
/// `TerminalApp` に準拠する型のインスタンスプロパティや、`View` の `@State` を付けたプロパティを書き換える。
/// 値を取得するクロージャと書き換えるクロージャの組を持つだけの値型で、プロパティは `Binding` の中へ移らない。
///
/// - Note: `TextField`・`ListView` に `Binding` で渡したプロパティを書き換えるのは、`TextFieldState.handle(_: InputEvent)`・
///   `ListState.handle(_:)`・`ListState.select(_:)` など、`TextFieldState`・`ListState` のメソッドだけ。
///   `TextField`・`ListView` の `View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` では値を取得するだけ。
/// - Warning: TUIKit を使う開発者が書く `View` の `View.body`・`View.sizeThatFits(_:context:)`・`View.layoutTraits(context:)`・
///   `View.render(into:rect:context:)` の中で `wrappedValue` へ代入すると、`Application.draw()` の 1 回のうちに
///   同じ `View` を何度も辿るため、`View.sizeThatFits(_:context:)` で取得した値と
///   `View.render(into:rect:context:)` で取得した値が食い違う。
@MainActor
public struct Binding<Value> {
    private let getValue: @MainActor () -> Value
    private let setValue: @MainActor (Value) -> Void

    /// 値を取得するクロージャと書き換えるクロージャを指定して `Binding` を作る。
    ///
    /// - Parameters:
    ///   - get: プロパティの現在の値を返すクロージャ。
    ///   - set: 新しい値でプロパティを書き換えるクロージャ。
    public init(get: @escaping @MainActor () -> Value, set: @escaping @MainActor (Value) -> Void) {
        self.getValue = get
        self.setValue = set
    }

    /// `root` のプロパティの値を取得し、書き換える `Binding` を作る。
    ///
    /// - Parameters:
    ///   - root: `keyPath` のプロパティを持つインスタンス。
    ///   - keyPath: 値を取得し、書き換えるプロパティ。
    /// - Note: `root` を強く参照する。`TextField(text:state:)` や `ListView(items:selection:state:)` に
    ///   渡した `Binding` は `TextFieldState`・`ListState` が持ち続けるので、`root` がその `TextFieldState` か
    ///   `ListState` を持っていれば、どちらも解放されない。
    public init<Root: AnyObject>(_ root: Root, _ keyPath: ReferenceWritableKeyPath<Root, Value>) {
        self.init(
            get: { root[keyPath: keyPath] },
            set: { root[keyPath: keyPath] = $0 }
        )
    }

    /// 常に `value` を返し、代入された値を捨てる `Binding` を作る。
    ///
    /// - Parameters:
    ///   - value: 返す値。
    /// - Returns: `value` を返し続ける `Binding`。
    public static func constant(_ value: Value) -> Binding<Value> {
        Binding(get: { value }, set: { _ in })
    }

    /// プロパティの現在の値。代入するとプロパティを書き換える。
    public var wrappedValue: Value {
        get { getValue() }
        nonmutating set { setValue(newValue) }
    }
}
