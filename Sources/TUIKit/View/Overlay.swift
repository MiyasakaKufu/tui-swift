/// 同じ矩形へ重ねるときの子ビューの配置。
@MainActor
enum OverlayLayout {

    /// 重ねる子ビューに割り当てる矩形を求める。
    ///
    /// - Parameters:
    ///   - child: 重ねて描く子ビュー。
    ///   - index: 親の中での子の番号。
    ///   - rect: 重ね先の矩形。
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    ///   - context: 親が受け取った文脈。
    /// - Returns: `rect` に収まる、子ビューの矩形。伸びる子ビューは `rect` いっぱいを受け取る。
    static func childRect(
        for child: any View,
        index: Int,
        in rect: Rect,
        horizontal: HorizontalAlignment,
        vertical: VerticalAlignment,
        context: RenderContext
    ) -> Rect {
        let traits = context.layoutTraits(of: child, index: index)
        let desired = context.sizeThatFits(of: child, index: index, proposal: rect.size)
        let width = traits.horizontalFlex > 0 ? rect.width : min(desired.width, rect.width)
        let height = traits.verticalFlex > 0 ? rect.height : min(desired.height, rect.height)
        return Rect(
            x: rect.minX + horizontal.offset(content: width, available: rect.width),
            y: rect.minY + vertical.offset(content: height, available: rect.height),
            width: width,
            height: height
        )
    }
}

/// 子ビューを同じ矩形へ重ねて描く。
///
/// 並びの後ろにあるビューほど手前に描かれる。下のビューを確実に覆うには、重ねるビューの側で
/// `background(style:)` や `Fill` を使って領域を塗る。
public struct ZStack: PrimitiveView {
    /// 重ねる子ビュー。先頭が最背面。
    public var children: [any View]
    /// 子ビューを横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 子ビューを縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// 寄せる向きを指定し、クロージャで子ビューを重ねる。
    ///
    /// - Parameters:
    ///   - horizontal: 子ビューを横に寄せる向き。
    ///   - vertical: 子ビューを縦に寄せる向き。
    ///   - content: 重ねる子ビューを返すクロージャ。
    public init(
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center,
        @ViewBuilder content: () -> [any View]
    ) {
        self.children = content()
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 子ビューの配列を直接渡して作る。
    ///
    /// - Parameters:
    ///   - children: 重ねる子ビュー。先頭が最背面。
    ///   - horizontal: 子ビューを横に寄せる向き。
    ///   - vertical: 子ビューを縦に寄せる向き。
    public init(
        children: [any View],
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) {
        self.children = children
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 子ビューのうち最も大きい重みを返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 方向ごとに、子ビューの重みの最大をとった性質。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        let traits = children.enumerated().map { context.layoutTraits(of: $1, index: $0) }
        return LayoutTraits(
            horizontalFlex: traits.map(\.horizontalFlex).max() ?? 0,
            verticalFlex: traits.map(\.verticalFlex).max() ?? 0
        )
    }

    /// 最も大きい子ビューに合わせたサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 幅・高さのそれぞれで最大の子に合わせたサイズ。`proposal` は超えない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        guard !children.isEmpty else { return .zero }
        var width = 0
        var height = 0
        for (index, child) in children.enumerated() {
            let desired = context.sizeThatFits(of: child, index: index, proposal: proposal)
            width = max(width, desired.width)
            height = max(height, desired.height)
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    /// 子ビューを同じ矩形へ順に描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        for (index, child) in children.enumerated() {
            let childRect = OverlayLayout.childRect(
                for: child,
                index: index,
                in: rect,
                horizontal: horizontal,
                vertical: vertical,
                context: context
            )
            context.render(child, index: index, into: &buffer, rect: childRect)
        }
    }
}

/// 内容の上へ、レイアウトに加わらないビューを重ねるビュー。
///
/// 重ねるビューはサイズの計算にも余白の分配にも加わらないため、これを挟んでも親のレイアウトは
/// 変わらない。
public struct OverlayView<Content: View, Overlay: View>: PrimitiveView {
    /// 下に敷く内容。
    public var content: Content
    /// 内容の上へ重ねるビュー。
    public var overlay: Overlay
    /// 重ねるビューを横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 重ねるビューを縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// 内容と、その上へ重ねるビューを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 下に敷く内容。
    ///   - overlay: 内容の上へ重ねるビュー。
    ///   - horizontal: 重ねるビューを横に寄せる向き。
    ///   - vertical: 重ねるビューを縦に寄せる向き。
    public init(
        content: Content,
        overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) {
        self.content = content
        self.overlay = overlay
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 内容の性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の、余白の分配に関する性質。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// 内容の希望サイズをそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズ。重ねるビューの大きさは影響しない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// 内容を描いてから、その上へ重ねるビューを描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        context.render(content, index: 0, into: &buffer, rect: rect)
        let overlayRect = OverlayLayout.childRect(
            for: overlay,
            index: 1,
            in: rect,
            horizontal: horizontal,
            vertical: vertical,
            context: context
        )
        context.render(overlay, index: 1, into: &buffer, rect: overlayRect)
    }
}

/// 内容の上へ、画面全体を基準に置いたビューを重ねるビュー。
///
/// 重ねるビューは親から渡された矩形ではなく `RenderContext.screen` を基準に配置されるため、
/// 画面の中央へダイアログを出せる。
///
/// - Warning: 重ねるビューは `render(into:rect:context:)` に渡された矩形の外へも描く。`View` が約束する
///   「`rect` の外のセルは書き換えない」から外れる唯一のビュー。
/// - Note: 重ねるビューが描かれるのは、このビューが描かれた時点。後から描かれる兄弟ビューには
///   上書きされるので、いちばん外側のビューへ付ける。
public struct ScreenOverlayView<Content: View, Overlay: View>: PrimitiveView {
    /// 下に敷く内容。
    public var content: Content
    /// 画面全体を基準に重ねるビュー。
    public var overlay: Overlay
    /// 重ねるビューを画面の横方向で寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 重ねるビューを画面の縦方向で寄せる向き。
    public var vertical: VerticalAlignment

    /// 内容と、画面全体を基準に重ねるビューを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 下に敷く内容。
    ///   - overlay: 画面全体を基準に重ねるビュー。
    ///   - horizontal: 重ねるビューを画面の横方向で寄せる向き。
    ///   - vertical: 重ねるビューを画面の縦方向で寄せる向き。
    public init(
        content: Content,
        overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) {
        self.content = content
        self.overlay = overlay
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 内容の性質を返す。
    ///
    /// - Parameters:
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の、余白の分配に関する性質。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// 内容の希望サイズをそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズ。重ねるビューの大きさは影響しない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// 内容を描いてから、画面全体を基準に重ねるビューを描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 内容を描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(content, index: 0, into: &buffer, rect: rect)
        let screen = context.screen
        guard !screen.isEmpty else { return }
        let overlayRect = OverlayLayout.childRect(
            for: overlay,
            index: 1,
            in: screen,
            horizontal: horizontal,
            vertical: vertical,
            context: context
        )
        context.render(overlay, index: 1, into: &buffer, rect: overlayRect)
    }
}

extension View {
    /// レイアウトとサイズを変えずに、上へビューを重ねる。
    ///
    /// - Parameters:
    ///   - overlay: 上へ重ねるビュー。
    ///   - horizontal: 重ねるビューを横に寄せる向き。
    ///   - vertical: 重ねるビューを縦に寄せる向き。
    /// - Returns: ビューを重ねたビュー。
    public func overlay<Overlay: View>(
        _ overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> OverlayView<Self, Overlay> {
        OverlayView(content: self, overlay: overlay, horizontal: horizontal, vertical: vertical)
    }

    /// 画面全体を基準にして、上へビューを重ねる。
    ///
    /// - Parameters:
    ///   - overlay: 上へ重ねるビュー。
    ///   - horizontal: 重ねるビューを画面の横方向で寄せる向き。
    ///   - vertical: 重ねるビューを画面の縦方向で寄せる向き。
    /// - Returns: 画面全体を基準にビューを重ねたビュー。
    /// - Note: 重ねるビューが後から描かれる兄弟ビューに隠れないよう、いちばん外側のビューへ付ける。
    public func screenOverlay<Overlay: View>(
        _ overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> ScreenOverlayView<Self, Overlay> {
        ScreenOverlayView(content: self, overlay: overlay, horizontal: horizontal, vertical: vertical)
    }
}
