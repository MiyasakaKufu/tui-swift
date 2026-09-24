/// フレームをまたいで保持される、ビュー 1 つ分の記録。
///
/// - Invariant: `path` と `viewType` が同じビューが毎フレーム辿られる間は、同じノードが使われ続ける。
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
}

/// ビューのノードを、経路ごとにフレームをまたいで保持するもの。
///
/// 1 フレームは `renderFrame(_:into:ambiguousWidth:)` で描く。そのフレームで辿られた位置のノードは
/// 次のフレームへ持ち越し、辿られなかったノードは捨てる。
@MainActor
final class ViewGraph {
    /// 経路ごとのノード。
    private var nodes: [ViewPath: ViewNode] = [:]
    /// いま描いているフレームの番号。
    private var frame = 0
    /// 次に作るノードの同一性。
    private var nextID = 0

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

    /// `view` をルートとして 1 フレーム分を描く。
    ///
    /// - Parameters:
    ///   - view: ルートのビュー。
    ///   - buffer: 描画先のバッファ。画面全体として扱う。
    ///   - ambiguousWidth: 曖昧幅の文字の扱い。
    /// - Postcondition: このフレームで辿られなかった位置のノードを捨てる。
    func renderFrame(
        _ view: some View,
        into buffer: inout Buffer,
        ambiguousWidth: DisplayWidth.AmbiguousWidth
    ) {
        frame += 1

        let bounds = buffer.bounds
        let context = RenderContext(
            node: node(at: .root, viewType: type(of: view)),
            graph: self,
            screen: bounds,
            ambiguousWidth: ambiguousWidth
        )
        view.render(into: &buffer, rect: bounds, context: context)

        nodes = nodes.filter { $0.value.lastVisitedFrame == frame }
    }
}
