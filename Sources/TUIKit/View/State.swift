/// ``View`` が自分で持ち、`Application.draw()` をまたいで残る値。
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
/// 値は ``View`` の構造体の外にある記憶域に置かれる。``View`` は `Application.draw()` のたびに作り直されるが、前の `Application.draw()` と同じ記憶域が結び付くので、値は引き継がれる。どの記憶域が結び付くかは、``Application`` が最初にメソッドを呼び出す ``View`` からその ``View`` まで、``RenderContext`` のメソッドか ``ViewVisitor/visit(_:index:)`` に渡したときの `index:` 引数（``View/id(_:)`` で作った ``View`` を渡したときは ``View/id(_:)`` の引数）の並びと、``View`` の型で決まる。
///
/// ``Application`` が最初にメソッドを呼び出す ``View`` から先の ``View`` は、`Application.draw()` のたびに、レイアウトの計算と描画より前にもたどられる。たどられる ``View`` は、``View/body`` の値の ``View`` と、``PrimitiveView/visitChildren(_:)`` が ``ViewVisitor/visit(_:index:)`` に渡した ``View``。``State`` は、その ``View`` の ``View/body`` の値を取得するより前に記憶域へ結び付く。
///
/// ``TextField``・``ListView`` で値を変えるには、``View/body`` の中で `$` から得た ``Binding`` を ``TextField`` の `text:` 引数か ``ListView`` の `selection:` 引数へ渡す。フォーカスを持つ ``TextField``・``ListView`` が受け取った ``InputEvent`` で、`TextFieldState.handle(_: InputEvent)`・``ListState/handle(_:)`` が書き戻す。キーで値を変えるには、``View/onKeyPress(_:action:)`` に渡すクロージャの中で代入する。
///
/// - Note: 記憶域を捨てる規則は次の 2 つ。1 つ目は、`Application.draw()` の 1 回で、レイアウトの計算と描画より前にたどられず、``RenderContext/sizeThatFits(of:index:proposal:)``・``RenderContext/layoutTraits(of:index:)``・``RenderContext/render(_:index:into:rect:)`` のどれにも `child` 引数として渡されなかった ``View`` の記憶域を、その `Application.draw()` の終わりに捨てる（``Application`` が最初にメソッドを呼び出す ``View`` は除く）。`rect` 引数によってレイアウトの計算でも描画でも渡されなかった ``View`` の記憶域は、たどられていれば残る。
///   2 つ目は、`index:` 引数の並びが同じまま ``View`` の型が変わったら、前の型の ``View`` の記憶域と、前の型の ``View`` から先で `child` 引数として渡されていた ``View`` の記憶域を捨てる。どちらも、次に同じ `index:` 引数の並びで渡された ``View`` は初期値から始まる。
/// - Note: ``View`` に準拠する型の格納プロパティとして直接宣言する。``View`` が持つ別の構造体の中や、``Component`` に準拠する型に置いた ``State`` は記憶域に結び付かない。
/// - Note: ``View/body``、``View/sizeThatFits(_:context:)``、``View/layoutTraits(context:)``、``View/render(into:rect:context:)`` の中で読むと記憶域の値が返る。``State`` が記憶域に結び付く前（``View`` を作った直後など）は、読むと初期値を返し、代入は捨てる。そのときに `$` で得た ``Binding`` も初期値を返し続け、書き戻しを捨てる。
/// - Warning: 測定と描画（``View/sizeThatFits(_:context:)``、``View/layoutTraits(context:)``、``View/render(into:rect:context:)``、``View/body``）の中で代入しない。`Application.draw()` の 1 回のうちに同じ ``View`` を何度も辿るため、測ったときと描いたときで値が食い違う。
@MainActor
@propertyWrapper
public struct State<Value> {
    /// 記憶域がまだ無いときに使う値。
    private let initialValue: Value
    /// 結び付いた記憶域を指す `StateBox`。
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
    /// - Note: 返した ``Binding`` は、読んだ時点の ``View`` の記憶域を読み書きし続ける。``View`` が描かれなくなって記憶域が捨てられた後は、書き戻しても画面には出ない。
    public var projectedValue: Binding<Value> {
        guard let storage = box.storage else { return .constant(initialValue) }
        return Binding(get: { storage.value }, set: { storage.value = $0 })
    }
}

/// ``View`` に準拠する型の中で、記憶域へ結び付ける対象になるプロパティ。
@MainActor
protocol StateProperty {
    /// `node` の記憶域のうち、`label` の分へ結び付ける。
    ///
    /// - Parameters:
    ///   - node: 記憶域を持つ `ViewNode`。
    ///   - label: ``View`` に準拠する型の中でのプロパティの名前。
    ///   - graph: `node` を持つ `ViewGraph`。
    func bind(to node: ViewNode, label: String, in graph: ViewGraph)
}

extension State: StateProperty {
    /// `node` の記憶域のうち、`label` の分へ結び付ける。無ければ初期値で作る。
    ///
    /// - Parameters:
    ///   - node: 記憶域を持つ `ViewNode`。
    ///   - label: ``View`` に準拠する型の中でのプロパティの名前。
    ///   - graph: `node` を持つ `ViewGraph`。
    func bind(to node: ViewNode, label: String, in graph: ViewGraph) {
        box.storage = node.storage(for: label, initialValue: initialValue)
    }
}

/// ``State`` が結び付いた記憶域を指すクラス。
@MainActor
final class StateBox<Value> {
    /// 結び付いた記憶域。結び付く前は `nil`。
    var storage: StateStorage<Value>?
}

/// `ViewNode` が持つ、``State`` 1 つ分の記憶域。
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
