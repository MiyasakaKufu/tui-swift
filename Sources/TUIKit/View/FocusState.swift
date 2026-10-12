/// フォーカスを持つ ``View`` を表し、代入でフォーカスを移すプロパティの型。
///
/// ``View/focused(_:equals:)`` か ``View/focused(_:)`` に `$` から得た ``FocusState/Binding`` を渡して、``View`` と結び付ける。フォーカスが結び付いた ``View`` にある間はその値になり、無い間は `nil`（`Bool` なら `false`）になる。代入すると、その値に結び付いた ``View`` へフォーカスが移る。
///
/// ```swift
/// struct LoginForm: View {
///     enum Field: Hashable {
///         case name
///         case note
///     }
///
///     @State private var name = ""
///     @State private var note = ""
///     @State private var nameState = TextFieldState()
///     @State private var noteState = TextFieldState()
///     @FocusState private var focusedField: Field?
///
///     var body: some View {
///         VStack {
///             TextField(text: $name, state: nameState)
///                 .focused($focusedField, equals: .name)
///                 .onKeyPress(.enter) {
///                     focusedField = .note
///                     return .handled
///                 }
///             TextField(text: $note, state: noteState)
///                 .focused($focusedField, equals: .note)
///         }
///     }
/// }
/// ```
///
/// - Note: 値の型は Optional か `Bool` に限る。`nil`（`Bool` なら `false`）を代入すると、このプロパティを ``View/focused(_:equals:)``・``View/focused(_:)`` に渡した ``View`` からフォーカスを外す。ほかの ``View`` がフォーカスを持つときは変えない。外した後は、Tab か、フォーカスを移すクリックか、``FocusState`` を付けたプロパティへの代入か、``View/sheet(isPresented:content:)`` の `content:` の表示か閉じるまで、どの ``View`` もフォーカスを持たない。
/// - Note: 代入すると、直前の `Application.draw()` の 1 回でたどった ``View`` の一覧を使って、すぐフォーカスを移す。移す先がその一覧に無ければ、次の `Application.draw()` の 1 回で、描画より前に 1 回だけ移すことを試みる。試みる前に Tab・フォーカスを移すクリック・別の代入があれば、試みない。
/// - Note: ``State`` と同じく、``View`` に準拠する型の格納プロパティとして直接宣言する。``Component`` に準拠する型に置いた ``FocusState`` は記憶域に結び付かず、値は `nil`（`Bool` なら `false`）のまま変わらず、代入は捨てる。
@MainActor
@propertyWrapper
public struct FocusState<Value: Hashable> {
    /// フォーカスが結び付いた ``View`` に無いときの値。
    private let resetValue: Value
    /// 結び付いた記憶域を指す `FocusStateBox`。
    private let box = FocusStateBox<Value>()

    /// `Bool` の値を持つ ``FocusState`` を作る。結び付いた ``View`` の内側のどれかがフォーカスを持つ間は `true` になる。
    public init() where Value == Bool {
        self.resetValue = false
    }

    /// Optional の値を持つ ``FocusState`` を作る。フォーカスを持つ ``View`` に結び付いた値になる。
    public init<Wrapped: Hashable>() where Value == Wrapped? {
        self.resetValue = nil
    }

    /// フォーカスを持つ ``View`` に結び付いた値。代入するとフォーカスを移す。
    public var wrappedValue: Value {
        get { box.storage?.value ?? resetValue }
        nonmutating set { box.storage?.assign(newValue) }
    }

    /// ``View/focused(_:equals:)``・``View/focused(_:)`` に渡す ``FocusState/Binding``。
    public var projectedValue: Binding {
        Binding(storage: box.storage, resetValue: resetValue)
    }

    /// ``View/focused(_:equals:)``・``View/focused(_:)`` で ``View`` に結び付ける、``FocusState`` の値を取得し、代入する型。
    @MainActor
    @propertyWrapper
    public struct Binding {
        /// 結び付いた記憶域。``FocusState`` が記憶域に結び付く前に得た ``FocusState/Binding`` では `nil`。
        let storage: FocusStateStorage<Value>?
        /// フォーカスが結び付いた ``View`` に無いときの値。
        let resetValue: Value

        /// フォーカスを持つ ``View`` に結び付いた値。代入するとフォーカスを移す。
        public var wrappedValue: Value {
            get { storage?.value ?? resetValue }
            nonmutating set { storage?.assign(newValue) }
        }

        /// この ``FocusState/Binding`` 自身。
        public var projectedValue: Binding { self }
    }
}

extension FocusState: StateProperty {
    /// `node` の記憶域のうち、`label` の分へ結び付ける。無ければ作る。
    ///
    /// - Parameters:
    ///   - node: 記憶域を持つ `ViewNode`。
    ///   - label: ``View`` に準拠する型の中でのプロパティの名前。
    ///   - environment: `node` を持つ `ViewGraph` の `ViewGraph.environment`。
    func bind(to node: ViewNode, label: String, environment: ViewEnvironment) {
        let resetValue = self.resetValue
        let storage = node.object(for: label) { FocusStateStorage(resetValue: resetValue) }
        storage.focus = environment.focus
        box.storage = storage
    }
}

/// ``FocusState`` が結び付いた記憶域を指すクラス。
@MainActor
final class FocusStateBox<Value: Hashable> {
    /// 結び付いた記憶域。結び付く前は `nil`。
    var storage: FocusStateStorage<Value>?
}

/// 型を消した `FocusStateStorage`。
@MainActor
protocol AnyFocusStateStorage: AnyObject {}

/// フォーカスを保持し、``View`` と ``FocusState`` にフォーカスを示す型。
@MainActor
protocol FocusProviding: AnyObject {
    /// `node` の ``View`` がフォーカスを持つかを返す。
    ///
    /// - Parameters:
    ///   - node: 調べる ``View`` の `ViewNode`。
    /// - Returns: フォーカスを持てば `true`。
    func isFocused(_ node: ViewNode) -> Bool

    /// `storage` に結び付いた ``View`` のうち、フォーカスを持つものの値を返す。
    ///
    /// - Parameters:
    ///   - storage: `@FocusState` を付けたプロパティの記憶域。
    /// - Returns: フォーカスを持つ ``View`` に `storage` が結び付いていればその値。結び付いていなければ `nil`。
    func focusedValue(of storage: any AnyFocusStateStorage) -> AnyHashable?

    /// `@FocusState` を付けたプロパティへの代入を、フォーカスへ反映する。
    ///
    /// - Parameters:
    ///   - value: 代入された値。`nil`（`Bool` なら `false`）が代入されたなら `nil`。
    ///   - storage: 代入された `@FocusState` を付けたプロパティの記憶域。
    func assign(_ value: AnyHashable?, to storage: any AnyFocusStateStorage)
}

/// `ViewNode` が持つ、``FocusState`` 1 つ分の記憶域。
@MainActor
final class FocusStateStorage<Value: Hashable>: AnyFocusStateStorage {
    /// フォーカスを保持する `FocusProviding`。``RenderContext/init(screen:ambiguousWidth:)`` で作った ``RenderContext`` から結び付いたときは `nil`。
    weak var focus: (any FocusProviding)?
    /// フォーカスが結び付いた ``View`` に無いときの値。
    let resetValue: Value

    /// 記憶域を作る。
    ///
    /// - Parameters:
    ///   - resetValue: フォーカスが結び付いた ``View`` に無いときの値。
    init(resetValue: Value) {
        self.resetValue = resetValue
    }

    /// フォーカスを持つ ``View`` に結び付いた値。どれにも結び付いていなければ `FocusStateStorage.resetValue`。
    var value: Value {
        guard let focused = focus?.focusedValue(of: self) else { return resetValue }
        return focused.base as? Value ?? resetValue
    }

    /// `newValue` に結び付いた ``View`` へフォーカスを移すよう `FocusController` に求める。
    ///
    /// - Parameters:
    ///   - newValue: 代入された値。
    func assign(_ newValue: Value) {
        focus?.assign(newValue == resetValue ? nil : AnyHashable(newValue), to: self)
    }
}

/// ``FocusedView/content`` に ``FocusState`` を結び付ける ``View``。``View/focused(_:equals:)``・``View/focused(_:)`` で作る。
public struct FocusedView<Content: View, Value: Hashable>: View {
    /// ``FocusState`` を結び付ける ``View``。
    public var content: Content
    /// 結び付ける ``FocusState`` の ``FocusState/Binding``。
    public var binding: FocusState<Value>.Binding
    /// フォーカスが ``FocusedView/content`` にあるときの ``FocusState`` の値。
    public var value: Value
    /// ``View/focused(_:)`` で作ったなら `true`。``FocusedView/content`` の内側のどの ``View`` がフォーカスを持っても当てはまる。
    let includesDescendants: Bool

    /// ``FocusState`` を結び付けた ``View`` を作る。
    ///
    /// - Parameters:
    ///   - content: ``FocusState`` を結び付ける ``View``。
    ///   - binding: 結び付ける ``FocusState`` の ``FocusState/Binding``。
    ///   - value: フォーカスが `content` にあるときの ``FocusState`` の値。
    ///   - includesDescendants: `content` の内側のどの ``View`` がフォーカスを持っても当てはめるなら `true`。
    init(content: Content, binding: FocusState<Value>.Binding, value: Value, includesDescendants: Bool) {
        self.content = content
        self.binding = binding
        self.value = value
        self.includesDescendants = includesDescendants
    }

    /// ``FocusState`` を結び付けた ``FocusedView/content``。
    public var body: Content { content }
}

/// ``View/focused(_:equals:)``・``View/focused(_:)`` で作った ``View`` が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol FocusBindingView {
    /// 結び付ける ``FocusState`` の記憶域。``FocusState`` が記憶域に結び付く前に作った ``View`` では `nil`。
    var focusStorage: (any AnyFocusStateStorage)? { get }
    /// フォーカスがこの ``View`` の内側にあるときの ``FocusState`` の値。
    var focusValue: AnyHashable { get }
    /// ``View/focused(_:)`` で作ったなら `true`。
    var matchesAnyDescendant: Bool { get }
}

extension FocusedView: FocusBindingView {
    /// 結び付ける ``FocusState`` の記憶域。
    var focusStorage: (any AnyFocusStateStorage)? { binding.storage }
    /// フォーカスが ``FocusedView/content`` にあるときの ``FocusState`` の値。
    var focusValue: AnyHashable { AnyHashable(value) }
    /// ``View/focused(_:)`` で作ったなら `true`。
    var matchesAnyDescendant: Bool { includesDescendants }
}

extension View {
    /// フォーカスがこの ``View`` にある間、`binding` の値を `value` にする。`binding` に `value` を代入すると、この ``View`` へフォーカスを移す。
    ///
    /// - Parameters:
    ///   - binding: 結び付ける ``FocusState`` の ``FocusState/Binding``。`$` で得る。
    ///   - value: フォーカスがこの ``View`` にあるときの値。
    /// - Returns: `binding` を結び付けた ``FocusedView``。
    /// - Note: この ``View`` の内側で、たどった順で先頭のフォーカスを受け取る ``View``（``TextField``・``ListView``）がフォーカスを持つときに `value` になる。
    /// - Note: 同じ ``FocusState`` の同じ値を 2 つ以上の ``View`` に結び付けたときは、代入するとたどった順で先頭の ``View`` へフォーカスが移る。
    public func focused<Value: Hashable>(
        _ binding: FocusState<Value>.Binding,
        equals value: Value
    ) -> FocusedView<Self, Value> {
        FocusedView(content: self, binding: binding, value: value, includesDescendants: false)
    }

    /// この ``View`` の内側のどれかがフォーカスを持つ間、`condition` の値を `true` にする。`condition` に `true` を代入すると、この ``View`` へフォーカスを移す。
    ///
    /// - Parameters:
    ///   - condition: 結び付ける、`Bool` の値を持つ ``FocusState`` の ``FocusState/Binding``。`$` で得る。
    /// - Returns: `condition` を結び付けた ``FocusedView``。
    /// - Note: `true` を代入すると、この ``View`` の内側で、たどった順で先頭のフォーカスを受け取る ``View`` へフォーカスを移す。
    public func focused(_ condition: FocusState<Bool>.Binding) -> FocusedView<Self, Bool> {
        FocusedView(content: self, binding: condition, value: true, includesDescendants: true)
    }
}
