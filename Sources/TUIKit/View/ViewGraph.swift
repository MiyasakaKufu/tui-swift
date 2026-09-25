/// フレームをまたいで保持される、ビュー 1 つ分の記録。
///
/// - Invariant: `path` と `viewType` が同じビューが毎フレーム辿られる間は、同じノードが使われ続ける。
///   ノードが持つ `State` の記憶域も同じものが使われ続ける。
@MainActor
final class ViewNode {
    /// ビューの同一性。ノードを作り直すと別の値になる。
    let id: Int
    /// ビューが置かれている位置。
    let path: ViewPath
    /// ビューの型。型を知らずに作ったノードでは `nil`。
    let viewType: ObjectIdentifier?
    /// 最後に辿られたフレームの番号。
    var lastVisitedFrame: Int
    /// ビューの `State` の記憶域。プロパティの名前ごとに持つ。
    private var states: [String: AnyObject] = [:]

    /// ノードを作る。
    ///
    /// - Parameters:
    ///   - id: ビューの同一性。
    ///   - path: ビューが置かれている位置。
    ///   - viewType: ビューの型。
    ///   - frame: 作ったときのフレームの番号。
    init(id: Int, path: ViewPath, viewType: ObjectIdentifier?, frame: Int) {
        self.id = id
        self.path = path
        self.viewType = viewType
        self.lastVisitedFrame = frame
    }

    /// `label` の記憶域を返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - label: ビューの中でのプロパティの名前。
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

/// ビューのノードを、経路ごとにフレームをまたいで保持するもの。
///
/// 1 フレームは `renderFrame(_:into:ambiguousWidth:)` で描く。そのフレームで辿られた位置のノードは
/// 次のフレームへ持ち越し、辿られなかったノードは、持っている `State` の記憶域ごと捨てる。
@MainActor
final class ViewGraph {
    /// 経路ごとのノード。
    private var nodes: [ViewPath: ViewNode] = [:]
    /// いま描いているフレームの番号。
    private var frame = 0
    /// 次に作るノードの同一性。
    private var nextID = 0
    /// `State` を持たないと分かったビューの型。
    private var typesWithoutState: Set<ObjectIdentifier> = []

    /// 保持しているノードの数。
    var nodeCount: Int { nodes.count }

    /// `path` のノードを返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - path: ビューの経路。
    ///   - viewType: ビューの型。`nil` なら型を知らないノードとして扱う。
    /// - Returns: `path` のノード。前のフレームで同じ位置に別の型のビューがあったなら、
    ///   そのノードとその下のノードを捨てて作り直したもの。
    func node(at path: ViewPath, viewType: (any View.Type)?) -> ViewNode {
        let type = viewType.map { ObjectIdentifier($0) }
        if let node = nodes[path], node.viewType == type {
            node.lastVisitedFrame = frame
            return node
        }

        // 置き換える位置の下を残してはいけない。親が別のビューになっても、子が前のビューの
        // 同一性を引き継いでしまう。
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
    ///   - view: 結び付けるビュー。
    ///   - node: `view` のノード。
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

    /// `view` をルートとして 1 フレーム分を描く。
    ///
    /// - Parameters:
    ///   - view: ルートのビュー。
    ///   - buffer: 描画先のバッファ。画面全体として扱う。
    ///   - ambiguousWidth: 曖昧幅の文字の扱い。
    /// - Postcondition: このフレームで辿られなかった位置のノードを、`State` の記憶域ごと捨てる。
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
