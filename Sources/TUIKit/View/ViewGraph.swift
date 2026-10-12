/// `Application.draw()` をまたいで保持される、``View`` 1 つ分の記録。
///
/// - Invariant: `ViewNode.path` と `ViewNode.viewType` が同じ ``View`` が `Application.draw()` のたびに辿られる間は、同じ `ViewNode` が使われ続ける。`ViewNode` が持つ ``State`` の記憶域も同じものが使われ続ける。
@MainActor
final class ViewNode {
    /// ``View`` の同一性。`ViewNode` を作り直すと別の値になる。
    let id: Int
    /// ``View`` の `ViewPath`。
    let path: ViewPath
    /// ``View`` の型。型を知らずに作った `ViewNode` では `nil`。
    let viewType: ObjectIdentifier?
    /// 最後に辿られたときの、`ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しの通し番号。
    var lastVisitedFrame: Int
    /// ``View`` の ``State`` の記憶域。プロパティの名前ごとに持つ。
    private var states: [String: AnyObject] = [:]

    /// `ViewNode` を作る。
    ///
    /// - Parameters:
    ///   - id: ``View`` の同一性。
    ///   - path: ``View`` の `ViewPath`。
    ///   - viewType: ``View`` の型。
    ///   - frame: 作ったときの、`ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しの通し番号。
    init(id: Int, path: ViewPath, viewType: ObjectIdentifier?, frame: Int) {
        self.id = id
        self.path = path
        self.viewType = viewType
        self.lastVisitedFrame = frame
    }

    /// `label` の記憶域を返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - label: ``View`` に準拠する型の中でのプロパティの名前。
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

    /// `label` の記憶域を返す。無ければ `make` で作る。
    ///
    /// - Parameters:
    ///   - label: ``View`` に準拠する型の中でのプロパティの名前か、TUIKit の ``View`` が記憶域を区別するための名前。
    ///   - make: 記憶域を作るクロージャ。
    /// - Returns: `label` の記憶域。
    func object<Storage: AnyObject>(for label: String, make: () -> Storage) -> Storage {
        if let storage = states[label] as? Storage {
            return storage
        }
        let storage = make()
        states[label] = storage
        return storage
    }
}

/// ``View`` が ``Buffer`` へ書き込んだ矩形 1 つ分の記録。
struct HitRegion {
    /// ``Buffer`` へ書き込んだ ``View`` の `ViewPath`。
    let path: ViewPath
    /// ``View`` が ``Buffer`` へ書き込んだ矩形。
    let rect: Rect
}

/// `ViewNode` を、`ViewPath` ごとに `Application.draw()` をまたいで保持するもの。
///
/// `Application.draw()` の 1 回分は `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` で描く。その呼び出しで辿られた `ViewPath` の `ViewNode` は次の呼び出しへ持ち越し、辿られなかった `ViewNode` は、持っている ``State`` の記憶域ごと捨てる。
/// 辿られた `ViewPath` には、描画より前に `ViewGraph.visit(_:node:)` で辿った `ViewPath` と、``RenderContext`` のメソッドに `child` 引数として渡された ``View`` の `ViewPath` の両方が入る。
@MainActor
final class ViewGraph {
    /// `ViewGraph.visit(_:node:)` で辿った ``View`` と、その `ViewNode`。
    struct VisitedView {
        /// 辿った ``View``。
        let view: any View
        /// `VisitedView.view` の `ViewNode`。
        let node: ViewNode
    }

    /// `ViewPath` ごとの `ViewNode`。
    private var nodes: [ViewPath: ViewNode] = [:]
    /// いま描いている `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しの通し番号。
    private var frame = 0
    /// 次に作る `ViewNode` の `ViewNode.id`。
    private var nextID = 0
    /// ``State`` を持たないと分かった、``View`` に準拠する型。
    private var typesWithoutState: Set<ObjectIdentifier> = []
    /// いま描いている `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しで、`ViewGraph.visit(_:node:)` が辿った順に並べた `VisitedView`。
    private var visitedViews: [VisitedView] = []

    /// ``State`` などを結び付けるときと描画するときに、``View`` へ渡す `ViewEnvironment`。値は `ApplicationContext` が設定する。
    var environment = ViewEnvironment()

    /// 最後の `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しで、``View`` が ``Buffer`` へ書き込んだ矩形。書き込んだ順に並ぶ。
    private(set) var hitRegions: [HitRegion] = []

    /// 最後の `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しで描画された ``TextField`` が示した、端末エミュレータのカーソルの位置。`ViewNode.id` ごとに持つ。
    private(set) var cursorPoints: [Int: Point] = [:]

    /// 保持している `ViewNode` の数。
    var nodeCount: Int { nodes.count }

    /// `path` の `ViewNode` を返す。無ければ作る。
    ///
    /// - Parameters:
    ///   - path: ``View`` の `ViewPath`。
    ///   - viewType: ``View`` の型。`nil` なら型を知らない `ViewNode` として扱う。
    /// - Returns: `path` の `ViewNode`。前の `ViewGraph.renderFrame(_:into:ambiguousWidth:beforeRender:)` の呼び出しで同じ `ViewPath` に別の型の ``View`` があったなら、その `ViewNode` と、`path` で始まる `ViewPath` の `ViewNode` を捨てて作り直したもの。
    func node(at path: ViewPath, viewType: (any View.Type)?) -> ViewNode {
        let type = viewType.map { ObjectIdentifier($0) }
        if let node = nodes[path], node.viewType == type {
            node.lastVisitedFrame = frame
            return node
        }

        // `path` で始まる `ViewPath` の `ViewNode` を残してはいけない。残すと、`path` に別の型の `View` が来ても、その `View` が `child` 引数として渡す `View` が、前の型のときに作った `ViewNode`（と `State` の記憶域）をそのまま使ってしまう。
        if nodes[path] != nil {
            nodes = nodes.filter { !path.contains($0.key) }
        }
        let node = ViewNode(id: nextID, path: path, viewType: type, frame: frame)
        nextID += 1
        nodes[path] = node
        return node
    }

    /// `view` が ``Buffer`` へ書き込んだ矩形を記録する。
    ///
    /// - Parameters:
    ///   - rect: ``Buffer`` へ書き込んだ矩形。
    ///   - path: 書き込んだ ``View`` の `ViewPath`。
    func recordHitRegion(_ rect: Rect, path: ViewPath) {
        guard !rect.isEmpty else { return }
        hitRegions.append(HitRegion(path: path, rect: rect))
    }

    /// 描画された ``TextField`` が示した、端末エミュレータのカーソルの位置を記録する。
    ///
    /// - Parameters:
    ///   - point: カーソルを置く位置。
    ///   - node: ``TextField`` の `ViewNode`。
    func recordCursorPoint(_ point: Point, of node: ViewNode) {
        cursorPoints[node.id] = point
    }

    /// `view` の ``State`` と ``FocusState`` を、`node` の記憶域へ結び付ける。
    ///
    /// - Parameters:
    ///   - view: 結び付ける ``View``。
    ///   - node: `view` の `ViewNode`。
    /// - Note: 見るのは `view` が直接持つ格納プロパティだけ。別の構造体の中に置いた `State` は結び付かない。
    func bindState(of view: some View, to node: ViewNode) {
        let viewType = ObjectIdentifier(type(of: view))
        guard !typesWithoutState.contains(viewType) else { return }

        var hasState = false
        for child in Mirror(reflecting: view).children {
            guard let label = child.label, let property = child.value as? any StateProperty else { continue }
            property.bind(to: node, label: label, environment: environment)
            hasState = true
        }
        if !hasState {
            typesWithoutState.insert(viewType)
        }
    }

    /// `view` の ``State`` を `node` の記憶域へ結び付けてから、`view` が ``RenderContext`` のメソッドに `child` 引数として渡しうる ``View`` を辿る。
    ///
    /// ``PrimitiveView`` なら ``PrimitiveView/visitChildren(_:)`` が ``ViewVisitor/visit(_:index:)`` に渡した ``View`` を、そうでなければ ``View/body`` の値の ``View`` を、`index:` 引数を 0 として辿る。
    ///
    /// - Parameters:
    ///   - view: 辿る ``View``。
    ///   - node: `view` の `ViewNode`。
    func visit(_ view: some View, node: ViewNode) {
        // `View.body` の値の取得を、`ViewGraph.bindState(of:to:)` より前へ動かしてはいけない。`State` は結び付くまで初期値を返すので、`State` の値で `View.body` が返す `View` を変える `View` では、描画するのと違う `View` を辿ってしまう。
        bindState(of: view, to: node)
        visitedViews.append(VisitedView(view: view, node: node))
        let visitor = ViewVisitor(node: node, graph: self)
        if let primitive = view as? any PrimitiveView {
            primitive.visitChildren(visitor)
        } else {
            visitor.visit(view.body, index: 0)
        }
    }

    /// `view` を `ViewPath.root` に置き、`Application.draw()` の 1 回分を描く。
    ///
    /// 描画より前に、`view` から ``View`` を `ViewGraph.visit(_:node:)` で辿り終え、辿った順に並べた `VisitedView` を `beforeRender` に渡す。
    ///
    /// - Parameters:
    ///   - view: ``Application`` が最初にメソッドを呼び出す ``View``。
    ///   - buffer: 描画先の ``Buffer``。画面全体として扱う。
    ///   - ambiguousWidth: ``Cell`` の数を数えるときに使う ``DisplayWidth/AmbiguousWidth``。
    ///   - beforeRender: 描画より前に、`view` から辿った順に並べた `VisitedView` を受け取るクロージャ。
    /// - Postcondition: この呼び出しで辿られなかった `ViewPath` の `ViewNode` を、``State`` の記憶域ごと捨てる。`ViewGraph.visit(_:node:)` で辿った ``View`` の `ViewNode` は、レイアウトの計算でも描画でも ``RenderContext`` のメソッドに渡されなくても残る。
    func renderFrame(
        _ view: some View,
        into buffer: inout Buffer,
        ambiguousWidth: DisplayWidth.AmbiguousWidth,
        beforeRender: ([VisitedView]) -> Void = { _ in }
    ) {
        frame += 1

        let bounds = buffer.bounds
        let rootNode = node(at: .root, viewType: type(of: view))
        visit(view, node: rootNode)
        beforeRender(visitedViews)
        visitedViews = []
        hitRegions = []
        cursorPoints = [:]

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
