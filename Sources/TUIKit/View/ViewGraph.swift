/// `Application.draw()` をまたいで保持される、`View` 1 つ分の記録。
///
/// - Invariant: `path` と `viewType` が同じ `View` が `Application.draw()` のたびに辿られる間は、同じ `ViewNode` が
///   使われ続ける。`ViewNode` が持つ `State` の記憶域も同じものが使われ続ける。
@MainActor
final class ViewNode {
    /// `View` の同一性。`ViewNode` を作り直すと別の値になる。
    let id: Int
    /// `View` の `ViewPath`。
    let path: ViewPath
    /// `View` の型。型を知らずに作った `ViewNode` では `nil`。
    let viewType: ObjectIdentifier?
    /// 最後に辿られたときの、`ViewGraph.renderFrame(_:into:ambiguousWidth:)` の呼び出しの通し番号。
    var lastVisitedFrame: Int
    /// `View` の `State` の記憶域。プロパティの名前ごとに持つ。
    private var states: [String: AnyObject] = [:]

    /// `ViewNode` を作る。
    ///
    /// - Parameters:
    ///   - id: `View` の同一性。
    ///   - path: `View` の `ViewPath`。
    ///   - viewType: `View` の型。
    ///   - frame: 作ったときの、`ViewGraph.renderFrame(_:into:ambiguousWidth:)` の呼び出しの通し番号。
    init(id: Int, path: ViewPath, viewType: ObjectIdentifier?, frame: Int) {
        self.id = id
        self.path = path
        self.viewType = viewType
        self.lastVisitedFrame = frame
    }

    /// `label` の記憶域を返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - label: `View` に準拠する型の中でのプロパティの名前。
    ///   - initialValue: 記憶域を作るときの値。
    /// - Returns: `label` の記憶域。
    func storage<Value>(for label: String, initialValue: Value) -> StateStorage<Value> {
        if let storage = states[label] as? StateStorage<Value> {
            return storage
        }
        let storage = StateStorage(initialValue)
        states[label] = storage
        return storage
    }
}

/// `ViewNode` を、`ViewPath` ごとに `Application.draw()` をまたいで保持するもの。
///
/// `Application.draw()` の 1 回分は `renderFrame(_:into:ambiguousWidth:)` で描く。その呼び出しで辿られた `ViewPath` の
/// `ViewNode` は次の呼び出しへ持ち越し、辿られなかった `ViewNode` は、持っている `State` の記憶域ごと捨てる。
@MainActor
final class ViewGraph {
    /// `ViewPath` ごとの `ViewNode`。
    private var nodes: [ViewPath: ViewNode] = [:]
    /// いま描いている `renderFrame(_:into:ambiguousWidth:)` の呼び出しの通し番号。
    private var frame = 0
    /// 次に作る `ViewNode` の `ViewNode.id`。
    private var nextID = 0
    /// `State` を持たないと分かった、`View` に準拠する型。
    private var typesWithoutState: Set<ObjectIdentifier> = []

    /// 保持している `ViewNode` の数。
    var nodeCount: Int { nodes.count }

    /// `path` の `ViewNode` を返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - path: `View` の `ViewPath`。
    ///   - viewType: `View` の型。`nil` なら型を知らない `ViewNode` として扱う。
    /// - Returns: `path` の `ViewNode`。前の `renderFrame(_:into:ambiguousWidth:)` の呼び出しで同じ `ViewPath` に
    ///   別の型の `View` があったなら、その `ViewNode` と、`path` で始まる `ViewPath` の `ViewNode` を捨てて作り直したもの。
    func node(at path: ViewPath, viewType: (any View.Type)?) -> ViewNode {
        let type = viewType.map { ObjectIdentifier($0) }
        if let node = nodes[path], node.viewType == type {
            node.lastVisitedFrame = frame
            return node
        }

        // `path` で始まる `ViewPath` の `ViewNode` を残してはいけない。残すと、`path` に別の型の `View` が来ても、
        // その `View` が `child` 引数として渡す `View` が、前の型のときに作った `ViewNode`（と `State` の記憶域）を
        // そのまま使ってしまう。
        if nodes[path] != nil {
            nodes = nodes.filter { !path.contains($0.key) }
        }
        let node = ViewNode(id: nextID, path: path, viewType: type, frame: frame)
        nextID += 1
        nodes[path] = node
        return node
    }

    /// `view` の `State` を、`node` の記憶域へ結び付ける。
    ///
    /// - Parameters:
    ///   - view: 結び付ける `View`。
    ///   - node: `view` の `ViewNode`。
    /// - Note: 見るのは `view` が直接持つ格納プロパティだけ。別の構造体の中に置いた `State` は結び付かない。
    func bindState(of view: some View, to node: ViewNode) {
        let viewType = ObjectIdentifier(type(of: view))
        guard !typesWithoutState.contains(viewType) else { return }

        var hasState = false
        for child in Mirror(reflecting: view).children {
            guard let label = child.label, let property = child.value as? any StateProperty else { continue }
            property.bind(to: node, label: label)
            hasState = true
        }
        if !hasState {
            typesWithoutState.insert(viewType)
        }
    }

    /// `view` を `ViewPath.root` に置き、`Application.draw()` の 1 回分を描く。
    ///
    /// - Parameters:
    ///   - view: `Application` が最初にメソッドを呼び出す `View`。
    ///   - buffer: 描画先の `Buffer`。画面全体として扱う。
    ///   - ambiguousWidth: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    /// - Postcondition: この呼び出しで辿られなかった `ViewPath` の `ViewNode` を、`State` の記憶域ごと捨てる。
    func renderFrame(
        _ view: some View,
        into buffer: inout Buffer,
        ambiguousWidth: DisplayWidth.AmbiguousWidth
    ) {
        frame += 1

        let bounds = buffer.bounds
        let rootNode = node(at: .root, viewType: type(of: view))
        bindState(of: view, to: rootNode)
        let context = RenderContext(
            node: rootNode,
            graph: self,
            screen: bounds,
            ambiguousWidth: ambiguousWidth
        )
        view.render(into: &buffer, rect: bounds, context: context)

        nodes = nodes.filter { $0.value.lastVisitedFrame == frame }
    }
}
