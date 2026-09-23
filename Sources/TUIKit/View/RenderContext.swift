/// ビューツリーの中で、ビューが置かれている位置。
///
/// - Invariant: 親の経路と、親の中での子の番号だけで決まる。同じ子を何度測っても、測っただけで
///   描かなくても、描く途中で測り直しても、同じ子には同じ経路が振られる。
struct ViewPath: Hashable, Sendable {
    /// ルートから順に並べた、各段での子の番号。
    private var indices: [Int]

    /// ルートの経路。
    static let root = ViewPath(indices: [])

    /// 子の経路を返す。
    ///
    /// - Parameters:
    ///   - index: 親の中での子の番号。
    /// - Returns: この経路の下に `index` を足した経路。
    func appending(_ index: Int) -> ViewPath {
        ViewPath(indices: indices + [index])
    }
}

/// ビューがサイズを測り、描画するときに、ライブラリから渡される文脈。
///
/// 子を測るのも描くのも、子のメソッドを直接呼ばずに、この文脈を通す。
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
    /// このビューの経路。
    let path: ViewPath

    /// 画面全体の矩形。
    ///
    /// `ScreenOverlayView` は、親から渡された矩形ではなくこの矩形を基準に重ねるビューを置く。
    public let screen: Rect

    /// ルートのビューに渡す文脈を作る。
    ///
    /// - Parameters:
    ///   - screen: 画面全体の矩形。描画先のバッファ全体を渡す。
    public init(screen: Rect) {
        self.init(path: .root, screen: screen)
    }

    /// 経路を指定して文脈を作る。
    ///
    /// - Parameters:
    ///   - path: 文脈を渡すビューの経路。
    ///   - screen: 画面全体の矩形。
    private init(path: ViewPath, screen: Rect) {
        self.path = path
        self.screen = screen
    }

    /// 子のビューへ渡す文脈を返す。
    ///
    /// - Parameters:
    ///   - index: 親の中での子の番号。
    /// - Returns: 経路に `index` を足した文脈。
    func child(_ index: Int) -> RenderContext {
        RenderContext(path: path.appending(index), screen: screen)
    }

    /// 子のビューが希望するサイズを返す。
    ///
    /// - Parameters:
    ///   - child: 測る子のビュー。
    ///   - index: 親の中での子の番号。
    ///   - proposal: 子へ提案する領域の大きさ。
    /// - Returns: 子が希望するサイズ。
    public func sizeThatFits(of child: some View, index: Int, proposal: Size) -> Size {
        child.sizeThatFits(proposal, context: self.child(index))
    }

    /// 子のビューを描画する。
    ///
    /// - Parameters:
    ///   - child: 描く子のビュー。
    ///   - index: 親の中での子の番号。
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 子を描画する矩形。
    public func render(_ child: some View, index: Int, into buffer: inout Buffer, rect: Rect) {
        child.render(into: &buffer, rect: rect, context: self.child(index))
    }
}
