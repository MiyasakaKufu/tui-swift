/// ビューが自分で持ち、フレームをまたいで残る値。
///
/// ```swift
/// struct NameForm: View {
///     let inputState: TextFieldState
///     @State var name = ""
///
///     var body: some View {
///         VStack {
///             TextField(text: $name, state: inputState)
///             Text("\(name.count) 文字")
///         }
///     }
/// }
/// ```
///
/// 値はビューの構造体ではなく、ライブラリがビューの同一性ごとに持つ記憶域に置かれる。ビューは毎フレーム
/// 作り直されるが、同じ同一性のビューには同じ記憶域が結び付くので、値は前のフレームから引き継がれる。
/// 同一性は親の中での位置（`id(_:)` を付けたビューは鍵）と型で決まる。
///
/// ビューの外（イベントの処理など）から値を変えるには、`body` の中で `$` から得た `Binding` をウィジェットへ渡し、
/// ウィジェットの状態に書き戻させる。
///
/// - Note: 記憶域を捨てる規則は次の 2 つ。そのフレームで測られも、重みを読まれも、描かれもしなかった位置の記憶域は、
///   そのフレームの終わりに捨てる。同じ位置に別の型のビューが来たら、その位置と下の位置の記憶域を捨てる。
///   どちらも、次に同じ位置へ来たビューは初期値から始まる。
/// - Note: ビューの格納プロパティとして直接宣言する。ビューが持つ別の構造体の中や、`Component` に置いた
///   `State` は記憶域に結び付かない。
/// - Note: `body`、`sizeThatFits(_:context:)`、`layoutTraits(context:)`、`render(into:rect:context:)` の中で
///   読むと記憶域の値が返る。ライブラリがビューを辿る前（ビューを作った直後など）は、読むと初期値を返し、
///   代入は捨てる。そのときに `$` で得た `Binding` も初期値を返し続け、書き戻しを捨てる。
/// - Warning: 測定と描画（`sizeThatFits(_:context:)`、`layoutTraits(context:)`、`render(into:rect:context:)`、
///   `body`）の中で代入しない。1 フレームのうちに同じビューを何度も辿るため、測ったときと描いたときで
///   値が食い違う。
@MainActor
@propertyWrapper
public struct State<Value> {
    /// 記憶域がまだ無いときに使う値。
    private let initialValue: Value
    /// 結び付いた記憶域を指す小箱。
    private let box = StateBox<Value>()

    /// 初期値を指定して作る。
    ///
    /// - Parameters:
    ///   - wrappedValue: 記憶域がまだ無いときに使う値。
    public init(wrappedValue: Value) {
        self.initialValue = wrappedValue
    }

    /// 記憶域にある現在の値。代入すると記憶域へ書き込む。
    public var wrappedValue: Value {
        get {
            guard let storage = box.storage else { return initialValue }
            return storage.value
        }
        nonmutating set {
            box.storage?.value = newValue
        }
    }

    /// 記憶域を読み書きする `Binding`。
    ///
    /// - Note: 返した `Binding` は、読んだ時点のビューの記憶域を読み書きし続ける。ビューが描かれなくなって
    ///   記憶域が捨てられた後は、書き戻しても画面には出ない。
    public var projectedValue: Binding<Value> {
        guard let storage = box.storage else { return .constant(initialValue) }
        return Binding(get: { storage.value }, set: { storage.value = $0 })
    }
}

/// ビューの中で、記憶域へ結び付ける対象になるプロパティ。
@MainActor
protocol StateProperty {
    /// `node` の記憶域のうち、`label` の分へ結び付ける。
    ///
    /// - Parameters:
    ///   - node: 記憶域を持つノード。
    ///   - label: ビューの中でのプロパティの名前。
    func bind(to node: ViewNode, label: String)
}

extension State: StateProperty {
    /// `node` の記憶域のうち、`label` の分へ結び付ける。無ければ初期値で作る。
    ///
    /// - Parameters:
    ///   - node: 記憶域を持つノード。
    ///   - label: ビューの中でのプロパティの名前。
    func bind(to node: ViewNode, label: String) {
        box.storage = node.storage(for: label, initialValue: initialValue)
    }
}

/// `State` が結び付いた記憶域を指す小箱。
@MainActor
final class StateBox<Value> {
    /// 結び付いた記憶域。結び付く前は `nil`。
    var storage: StateStorage<Value>?
}

/// ノードが持つ、`State` 1 つ分の記憶域。
@MainActor
final class StateStorage<Value> {
    /// 現在の値。
    var value: Value

    /// 値を指定して記憶域を作る。
    ///
    /// - Parameters:
    ///   - value: 最初の値。
    init(_ value: Value) {
        self.value = value
    }
}
