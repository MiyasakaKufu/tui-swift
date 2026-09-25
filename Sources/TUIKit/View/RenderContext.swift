/// ビューツリーの中で、ビューが置かれている位置。
///
/// - Invariant: 親の経路と、親の中での子の番号（`id(_:)` で鍵を付けた子は鍵）だけで決まる。
///   同じ子を何度測っても、測っただけで描かなくても、描く途中で測り直しても、同じ子には同じ経路が振られる。
struct ViewPath: Hashable {
    /// 経路の 1 段。
    enum Component: Hashable {
        /// 親の中での子の番号。
        case index(Int)
        /// `id(_:)` で付けた鍵。
        case key(AnyHashable)
    }

    /// ルートから順に並べた、各段での子の位置。
    private var components: [Component]

    /// ルートの経路。
    static var root: ViewPath { ViewPath(components: []) }

    /// 子の経路を返す。
    ///
    /// - Parameters:
    ///   - component: 親の中での子の位置。
    /// - Returns: この経路の下に `component` を足した経路。
    func appending(_ component: Component) -> ViewPath {
        ViewPath(components: components + [component])
    }

    /// `other` がこの経路と同じか、この経路の下にあるかを返す。
    ///
    /// - Parameters:
    ///   - other: 調べる経路。
    /// - Returns: `other` がこの経路で始まるなら `true`。
    func contains(_ other: ViewPath) -> Bool {
        other.components.starts(with: components)
    }
}

/// ビューがサイズを測り、描画するときに、ライブラリから渡される文脈。
///
/// 子を測るのも、子の重みを読むのも、子を描くのも、子のメソッドを直接呼ばずに、この文脈を通す。
///
/// ```swift
/// func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
///     context.render(content, index: 0, into: &buffer, rect: rect.inset(by: 1))
/// }
/// ```
///
/// - Note: `index` は親の中で子を区別する番号で、同じ子にはレイアウトと描画で同じ番号を渡す。
///   `children` の並びのように、子の位置で決まる値を使う。
@MainActor
public struct RenderContext {
    /// このビューのノード。
    let node: ViewNode

    /// ノードを持つグラフ。
    let graph: ViewGraph

    /// このビューの経路。
    var path: ViewPath { node.path }

    /// 画面全体の矩形。
    ///
    /// `ScreenOverlayView` は、親から渡された矩形ではなくこの矩形を基準に重ねるビューを置く。
    public let screen: Rect

    /// East Asian Width が Ambiguous の文字を何桁として扱うか。
    ///
    /// - Note: `DisplayWidth` の各関数は、`ambiguous` を省くと `DisplayWidth.defaultAmbiguousWidth`
    ///   で測る。文字列の幅を測るときはこの値を渡す。渡さないと、アプリが指定した扱いと測った幅が
    ///   食い違い、その行の桁がずれる。
    public let ambiguousWidth: DisplayWidth.AmbiguousWidth

    /// ルートのビューに渡す文脈を作る。
    ///
    /// - Parameters:
    ///   - screen: 画面全体の矩形。描画先のバッファ全体を渡す。
    ///   - ambiguousWidth: 曖昧幅の文字の扱い。
    /// - Precondition: `ambiguousWidth` が描画先のバッファの `ambiguousWidth` と同じ。
    ///   違うと、ビューが測った幅とバッファに置かれるセルの桁が食い違う。
    /// - Note: 作るたびに新しいノードのグラフを使う。前に作った文脈で辿ったビューとは、
    ///   同じ位置にあっても同一性を共有しない。
    public init(
        screen: Rect,
        ambiguousWidth: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) {
        let graph = ViewGraph()
        self.init(
            node: graph.node(at: .root, viewType: nil),
            graph: graph,
            screen: screen,
            ambiguousWidth: ambiguousWidth
        )
    }

    /// ノードを指定して文脈を作る。
    ///
    /// - Parameters:
    ///   - node: 文脈を渡すビューのノード。
    ///   - graph: `node` を持つグラフ。
    ///   - screen: 画面全体の矩形。
    ///   - ambiguousWidth: 曖昧幅の文字の扱い。
    init(node: ViewNode, graph: ViewGraph, screen: Rect, ambiguousWidth: DisplayWidth.AmbiguousWidth) {
        self.node = node
        self.graph = graph
        self.screen = screen
        self.ambiguousWidth = ambiguousWidth
    }

    /// 子のビューへ渡す文脈を返す。
    ///
    /// - Parameters:
    ///   - child: 文脈を渡す子のビュー。
    ///   - index: 親の中での子の番号。
    /// - Returns: 子のノードを持つ文脈。`child` に鍵が付いていれば、経路には `index` の代わりに鍵を足す。
    func context(for child: some View, index: Int) -> RenderContext {
        let component: ViewPath.Component
        if let identified = child as? any ExplicitlyIdentified {
            component = .key(identified.identityKey)
        } else {
            component = .index(index)
        }
        let node = graph.node(at: path.appending(component), viewType: type(of: child))
        return RenderContext(node: node, graph: graph, screen: screen, ambiguousWidth: ambiguousWidth)
    }

    /// 子のビューが希望するサイズを返す。
    ///
    /// - Parameters:
    ///   - child: 測る子のビュー。
    ///   - index: 親の中での子の番号。
    ///   - proposal: 子へ提案する領域の大きさ。
    /// - Returns: 子が希望するサイズ。
    public func sizeThatFits(of child: some View, index: Int, proposal: Size) -> Size {
        child.sizeThatFits(proposal, context: context(for: child, index: index))
    }

    /// 子のビューの、余白の分配に関する性質を返す。
    ///
    /// - Parameters:
    ///   - child: 性質を読む子のビュー。
    ///   - index: 親の中での子の番号。
    /// - Returns: 子の性質。
    public func layoutTraits(of child: some View, index: Int) -> LayoutTraits {
        child.layoutTraits(context: context(for: child, index: index))
    }

    /// 子のビューを描画する。
    ///
    /// - Parameters:
    ///   - child: 描く子のビュー。
    ///   - index: 親の中での子の番号。
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 子を描画する矩形。
    public func render(_ child: some View, index: Int, into buffer: inout Buffer, rect: Rect) {
        child.render(into: &buffer, rect: rect, context: context(for: child, index: index))
    }
}
