/// `Application` が最初にメソッドを呼び出す `View` から、`RenderContext` のメソッドに `child` 引数として渡された
/// `View` を順にたどったときの、`ViewPath.Component` の並び。
///
/// - Invariant: `RenderContext` のメソッドに `child` 引数として渡した `View` の `ViewPath` は、その `RenderContext` の
///   `ViewPath` と、`index:` 引数（`child` が `View.id(_:)` で作った `View` なら `View.id(_:)` の引数）だけで決まる。
///   同じ `View` を何度測っても、測っただけで描かなくても、描く途中で測り直しても、同じ `View` には同じ `ViewPath` が振られる。
struct ViewPath: Hashable {
    /// `ViewPath` の 1 段。
    enum Component: Hashable {
        /// `RenderContext` のメソッドに渡した `index:` 引数。
        case index(Int)
        /// `View.id(_:)` の引数。
        case key(AnyHashable)
    }

    /// `ViewPath.root` から順に並べた `ViewPath.Component`。
    private var components: [Component]

    /// `ViewPath.Component` を 1 つも持たない `ViewPath`。
    ///
    /// `ViewGraph.renderFrame(_:into:ambiguousWidth:)` の `view` 引数と、`RenderContext.init(screen:ambiguousWidth:)` で
    /// 作った `RenderContext` を受け取る `View` に使う。
    static var root: ViewPath { ViewPath(components: []) }

    /// 末尾に `component` を足した `ViewPath` を返す。
    ///
    /// - Parameters:
    ///   - component: 末尾に足す `ViewPath.Component`。
    /// - Returns: この `ViewPath` の末尾に `component` を足した `ViewPath`。
    func appending(_ component: Component) -> ViewPath {
        ViewPath(components: components + [component])
    }

    /// `other` がこの `ViewPath` で始まるかを返す。
    ///
    /// - Parameters:
    ///   - other: 調べる `ViewPath`。
    /// - Returns: `other` がこの `ViewPath` で始まるなら `true`。
    func contains(_ other: ViewPath) -> Bool {
        other.components.starts(with: components)
    }
}

/// 別の `View` の `View.sizeThatFits(_:context:)`・`View.layoutTraits(context:)`・`View.render(into:rect:context:)` を
/// 呼び出すために、`View` が `context` 引数で受け取る型。
///
/// 別の `View` のこれらのメソッドは直接呼び出さず、`RenderContext.sizeThatFits(of:index:proposal:)`・
/// `RenderContext.layoutTraits(of:index:)`・`RenderContext.render(_:index:into:rect:)` に `child` 引数として渡して呼び出す。
///
/// ```swift
/// func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
///     context.render(content, index: 0, into: &buffer, rect: rect.inset(by: 1))
/// }
/// ```
///
/// - Note: `index` は、`child` 引数として渡す `View` どうしを区別する番号で、同じ `View` には
///   `RenderContext.sizeThatFits(of:index:proposal:)`・`RenderContext.layoutTraits(of:index:)`・
///   `RenderContext.render(_:index:into:rect:)` で同じ番号を渡す。`VStack.children` の並びのように、
///   `View` の並びの中の位置で決まる値を使う。
@MainActor
public struct RenderContext {
    /// この `RenderContext` を受け取る `View` の `ViewNode`。
    let node: ViewNode

    /// `node` を持つ `ViewGraph`。
    let graph: ViewGraph

    /// この `RenderContext` を受け取る `View` の `ViewPath`。
    var path: ViewPath { node.path }

    /// 画面全体の矩形。
    ///
    /// `ScreenOverlayView` は、`ScreenOverlayView.overlay` を `View.render(into:rect:context:)` の `rect` 引数の矩形ではなくこの矩形を基準に置く。
    public let screen: Rect

    /// East Asian Width が Ambiguous の文字を `Cell` 何個分として扱うか。
    ///
    /// - Note: `DisplayWidth` の各関数は、`ambiguous` を省くと `DisplayWidth.defaultAmbiguousWidth`
    ///   で測る。文字列の幅を測るときはこの値を渡す。渡さないと、TUIKit を使う開発者が指定した扱いと測った幅が
    ///   食い違い、その行の文字の `Point.x` がずれる。
    public let ambiguousWidth: DisplayWidth.AmbiguousWidth

    /// `View` のメソッドを直接呼び出すときに渡す `RenderContext` を作る。
    ///
    /// - Parameters:
    ///   - screen: 画面全体の矩形。描画先の `Buffer` 全体を渡す。
    ///   - ambiguousWidth: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    /// - Precondition: `ambiguousWidth` が描画先の `Buffer` の `ambiguousWidth` と同じ。
    ///   違うと、`View` が測った幅と、`Buffer` に置かれる `Cell` の数が食い違う。
    /// - Note: 作るたびに新しい記憶域を使う。前に作った `RenderContext` で辿った `View` とは、
    ///   同じ `index:` 引数の並びで渡しても同一性を共有せず、`State` の記憶域も共有しない。
    /// - Note: この `RenderContext` を直接渡した `View` 自身の `State` は、記憶域に結び付かず初期値のままになる。
    ///   結び付くのは、この `RenderContext` のメソッドに `child` 引数として渡した `View` と、その先で
    ///   `RenderContext` のメソッドに `child` 引数として渡された `View`。
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

    /// `ViewNode` を指定して `RenderContext` を作る。
    ///
    /// - Parameters:
    ///   - node: この `RenderContext` を `context` 引数で受け取る `View` の `ViewNode`。
    ///   - graph: `node` を持つ `ViewGraph`。
    ///   - screen: 画面全体の矩形。
    ///   - ambiguousWidth: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    init(node: ViewNode, graph: ViewGraph, screen: Rect, ambiguousWidth: DisplayWidth.AmbiguousWidth) {
        self.node = node
        self.graph = graph
        self.screen = screen
        self.ambiguousWidth = ambiguousWidth
    }

    /// `child` に渡す `RenderContext` を返す。
    ///
    /// - Parameters:
    ///   - child: `RenderContext` を `context` 引数で受け取る `View`。
    ///   - index: 同じ `RenderContext` に `child` 引数として渡すほかの `View` と `child` を区別する番号。
    /// - Returns: `child` の `ViewNode` を持つ `RenderContext`。`child` が `View.id(_:)` で作った `View` なら、
    ///   `ViewPath` には `index` の代わりに `View.id(_:)` の引数を `.key(_:)` として足す。
    /// - Postcondition: `child` の `State` が、`child` の `ViewNode` の記憶域へ結び付いている。
    func context(for child: some View, index: Int) -> RenderContext {
        let component: ViewPath.Component
        if let identified = child as? any ExplicitlyIdentified {
            component = .key(identified.identityKey)
        } else {
            component = .index(index)
        }
        let node = graph.node(at: path.appending(component), viewType: type(of: child))
        graph.bindState(of: child, to: node)
        return RenderContext(node: node, graph: graph, screen: screen, ambiguousWidth: ambiguousWidth)
    }

    /// `child` の `View.sizeThatFits(_:context:)` の戻り値を返す。
    ///
    /// - Parameters:
    ///   - child: `View.sizeThatFits(_:context:)` を呼び出される `View`。
    ///   - index: 同じ `RenderContext` に `child` 引数として渡すほかの `View` と `child` を区別する番号。
    ///   - proposal: `child` の `View.sizeThatFits(_:context:)` に `proposal` 引数として渡す `Size`。
    /// - Returns: `child` の `View.sizeThatFits(_:context:)` の戻り値。
    public func sizeThatFits(of child: some View, index: Int, proposal: Size) -> Size {
        child.sizeThatFits(proposal, context: context(for: child, index: index))
    }

    /// `child` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - child: `View.layoutTraits(context:)` を呼び出される `View`。
    ///   - index: 同じ `RenderContext` に `child` 引数として渡すほかの `View` と `child` を区別する番号。
    /// - Returns: `child` の `View.layoutTraits(context:)` の戻り値。
    public func layoutTraits(of child: some View, index: Int) -> LayoutTraits {
        child.layoutTraits(context: context(for: child, index: index))
    }

    /// `child` を描画する。
    ///
    /// - Parameters:
    ///   - child: `View.render(into:rect:context:)` を呼び出される `View`。
    ///   - index: 同じ `RenderContext` に `child` 引数として渡すほかの `View` と `child` を区別する番号。
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: `child` を描画する矩形。
    public func render(_ child: some View, index: Int, into buffer: inout Buffer, rect: Rect) {
        child.render(into: &buffer, rect: rect, context: context(for: child, index: index))
    }
}
