/// 同じ矩形へ重ねる ``View`` の配置。
@MainActor
enum OverlayLayout {

    /// 重ねる ``ViewList/Element`` の ``View`` に割り当てる矩形を求める。
    ///
    /// - Parameters:
    ///   - element: 重ねて描く ``View`` を持つ ``ViewList/Element``。
    ///   - slot: `element` を ``RenderContext`` のメソッドに渡すときの `slot` 引数。
    ///   - rect: 重ね先の矩形。
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    ///   - context: ``ZStack`` が `context` 引数で受け取った ``RenderContext``。
    /// - Returns: `rect` に収まる、`element` の ``View`` の矩形。`element` の ``View`` の ``LayoutTraits/horizontalFlex``・``LayoutTraits/verticalFlex`` が 1 以上の方向では `rect` いっぱいになる。
    static func childRect(
        for element: ViewList.Element,
        slot: Int,
        in rect: Rect,
        horizontal: HorizontalAlignment,
        vertical: VerticalAlignment,
        context: RenderContext
    ) -> Rect {
        place(
            traits: context.layoutTraits(of: element, slot: slot),
            desired: context.sizeThatFits(of: element, slot: slot, proposal: rect.size),
            in: rect,
            horizontal: horizontal,
            vertical: vertical
        )
    }

    /// ``LayoutTraits`` と ``View/sizeThatFits(_:context:)`` の戻り値から、重ねる ``View`` に割り当てる矩形を求める。
    ///
    /// - Parameters:
    ///   - traits: 重ねて描く ``View`` の ``LayoutTraits``。
    ///   - desired: 重ねて描く ``View`` の ``View/sizeThatFits(_:context:)`` の戻り値。
    ///   - rect: 重ね先の矩形。
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    /// - Returns: `rect` に収まる矩形。`traits` の ``LayoutTraits/horizontalFlex``・``LayoutTraits/verticalFlex`` が 1 以上の方向では `rect` いっぱいになる。
    private static func place(
        traits: LayoutTraits,
        desired: Size,
        in rect: Rect,
        horizontal: HorizontalAlignment,
        vertical: VerticalAlignment
    ) -> Rect {
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

/// 中の ``View`` を同じ矩形へ重ねて描く ``View``。
///
/// ``ZStack/children`` の後ろにある ``View`` ほど手前に描かれる。下の ``View`` を確実に覆うには、重ねる ``View`` に ``View/background(_:)`` や ``Fill`` を使って領域を塗る。
public struct ZStack: PrimitiveView {
    /// 重ねる ``View`` の ``ViewList``。先頭が最背面。
    public var children: ViewList
    /// 中の ``View`` を横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 中の ``View`` を縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// 寄せる向きと、中の ``View`` を返すクロージャから ``ZStack`` を作る。
    ///
    /// - Parameters:
    ///   - horizontal: 中の ``View`` を横に寄せる向き。
    ///   - vertical: 中の ``View`` を縦に寄せる向き。
    ///   - content: 重ねる ``View`` を返すクロージャ。
    public init(
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center,
        @ViewBuilder content: () -> ViewList
    ) {
        self.children = content()
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 中の ``View`` の配列と寄せる向きから ``ZStack`` を作る。
    ///
    /// - Parameters:
    ///   - children: 重ねる ``View``。先頭が最背面。配列の中の位置を、``ViewBuilder`` のクロージャで書いた位置として使う。
    ///   - horizontal: 中の ``View`` を横に寄せる向き。
    ///   - vertical: 中の ``View`` を縦に寄せる向き。
    public init(
        children: [any View],
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) {
        self.children = ViewList(children)
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 中の ``View`` の ``LayoutTraits`` を、方向ごとに最大をとって返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``LayoutTraits/horizontalFlex``・``LayoutTraits/verticalFlex`` のそれぞれに、中の ``View`` での最大をとった ``LayoutTraits``。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        let traits = children.map { context.layoutTraits(of: $0, slot: 0) }
        return LayoutTraits(
            horizontalFlex: traits.map(\.horizontalFlex).max() ?? 0,
            verticalFlex: traits.map(\.verticalFlex).max() ?? 0
        )
    }

    /// 中の ``View`` のうち最も大きいものに合わせたサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:slot:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: 幅・高さのそれぞれで、中の ``View`` の ``View/sizeThatFits(_:context:)`` の戻り値の最大に合わせたサイズ。
    ///   `proposal` は超えない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        guard !children.isEmpty else { return .zero }
        var width = 0
        var height = 0
        for child in children {
            let desired = context.sizeThatFits(of: child, slot: 0, proposal: proposal)
            width = max(width, desired.width)
            height = max(height, desired.height)
        }
        return Size(width: min(width, proposal.width), height: min(height, proposal.height))
    }

    /// 中の ``View`` を同じ矩形へ順に描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        for child in children {
            let childRect = OverlayLayout.childRect(
                for: child,
                slot: 0,
                in: rect,
                horizontal: horizontal,
                vertical: vertical,
                context: context
            )
            context.render(child, slot: 0, into: &buffer, rect: childRect)
        }
    }

    /// ``ZStack/children`` の要素を、`slot` 引数を 0 として、並びの順に `visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        for child in children {
            visitor.visit(child, slot: 0)
        }
    }
}

/// ``OverlayView/content`` の上へ、レイアウトに加わらない ``OverlayView/overlay`` を重ねる ``View``。
///
/// ``OverlayView/overlay`` は ``View/sizeThatFits(_:context:)`` の戻り値にも ``LayoutTraits`` にも加わらないため、``OverlayView`` を ``RenderContext`` のメソッドに渡す ``View`` のレイアウトは、``OverlayView`` を挟んでも変わらない。
public struct OverlayView<Content: View, Overlay: View>: PrimitiveView {
    /// 下に敷く ``View``。
    public var content: Content
    /// ``OverlayView/content`` の上へ重ねる ``View``。
    public var overlay: Overlay
    /// ``OverlayView/overlay`` を横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// ``OverlayView/overlay`` を縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// 下に敷く ``View`` と、その上へ重ねる ``View`` から ``OverlayView`` を作る。
    ///
    /// - Parameters:
    ///   - content: 下に敷く ``View``。
    ///   - overlay: `content` の上へ重ねる ``View``。
    ///   - horizontal: `overlay` を横に寄せる向き。
    ///   - vertical: `overlay` を縦に寄せる向き。
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

    /// ``OverlayView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``OverlayView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: ViewList.Element(content), slot: 0)
    }

    /// ``OverlayView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:slot:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``OverlayView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。``OverlayView/overlay`` の大きさは影響しない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: ViewList.Element(content), slot: 0, proposal: proposal)
    }

    /// ``OverlayView/content`` を描いてから、その上へ ``OverlayView/overlay`` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        context.render(ViewList.Element(content), slot: 0, into: &buffer, rect: rect)
        let overlayRect = OverlayLayout.childRect(
            for: ViewList.Element(overlay),
            slot: 1,
            in: rect,
            horizontal: horizontal,
            vertical: vertical,
            context: context
        )
        context.render(ViewList.Element(overlay), slot: 1, into: &buffer, rect: overlayRect)
    }

    /// ``OverlayView/content`` を `slot` 引数を 0 として、``OverlayView/overlay`` を `slot` 引数を 1 として、`visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(ViewList.Element(content), slot: 0)
        visitor.visit(ViewList.Element(overlay), slot: 1)
    }
}

/// ``ScreenOverlayView/content`` の上へ、画面全体を基準に置いた ``ScreenOverlayView/overlay`` を重ねる ``View``。
///
/// ``ScreenOverlayView/overlay`` は ``View/render(into:rect:context:)`` の `rect` 引数の矩形ではなく ``RenderContext/screen`` を基準に配置されるため、画面の中央へダイアログを出せる。
///
/// - Warning: ``ScreenOverlayView/overlay`` は ``View/render(into:rect:context:)`` に渡された矩形の外へも描く。
///   ``View`` が約束する「`rect` の外の ``Cell`` は書き換えない」から外れる唯一の ``View``。
/// - Note: ``ScreenOverlayView/overlay`` が描かれるのは、``ScreenOverlayView`` が描かれた時点。後から描かれる ``View`` には上書きされるので、``ScreenOverlayView`` を、``Application`` が最初にメソッドを呼び出す ``View`` にする（``TerminalApp/body`` が ``View/screenOverlay(_:horizontal:vertical:)`` の戻り値を返すようにする）。
public struct ScreenOverlayView<Content: View, Overlay: View>: PrimitiveView {
    /// 下に敷く ``View``。
    public var content: Content
    /// 画面全体を基準に重ねる ``View``。
    public var overlay: Overlay
    /// ``ScreenOverlayView/overlay`` を画面の横方向で寄せる向き。
    public var horizontal: HorizontalAlignment
    /// ``ScreenOverlayView/overlay`` を画面の縦方向で寄せる向き。
    public var vertical: VerticalAlignment

    /// 下に敷く ``View`` と、画面全体を基準に重ねる ``View`` から ``ScreenOverlayView`` を作る。
    ///
    /// - Parameters:
    ///   - content: 下に敷く ``View``。
    ///   - overlay: 画面全体を基準に重ねる ``View``。
    ///   - horizontal: `overlay` を画面の横方向で寄せる向き。
    ///   - vertical: `overlay` を画面の縦方向で寄せる向き。
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

    /// ``ScreenOverlayView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``ScreenOverlayView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: ViewList.Element(content), slot: 0)
    }

    /// ``ScreenOverlayView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:slot:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``ScreenOverlayView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。``ScreenOverlayView/overlay`` の大きさは影響しない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: ViewList.Element(content), slot: 0, proposal: proposal)
    }

    /// ``ScreenOverlayView/content`` を描いてから、画面全体を基準に ``ScreenOverlayView/overlay`` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: ``ScreenOverlayView/content`` を描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(ViewList.Element(content), slot: 0, into: &buffer, rect: rect)
        let screen = context.screen
        guard !screen.isEmpty else { return }
        let overlayRect = OverlayLayout.childRect(
            for: ViewList.Element(overlay),
            slot: 1,
            in: screen,
            horizontal: horizontal,
            vertical: vertical,
            context: context
        )
        context.render(ViewList.Element(overlay), slot: 1, into: &buffer, rect: overlayRect)
    }

    /// ``ScreenOverlayView/content`` を `slot` 引数を 0 として、``ScreenOverlayView/overlay`` を `slot` 引数を 1 として、`visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(ViewList.Element(content), slot: 0)
        visitor.visit(ViewList.Element(overlay), slot: 1)
    }
}

extension View {
    /// レイアウトとサイズを変えずに、上へ ``View`` を重ねる。
    ///
    /// - Parameters:
    ///   - overlay: 上へ重ねる ``View``。
    ///   - horizontal: `overlay` を横に寄せる向き。
    ///   - vertical: `overlay` を縦に寄せる向き。
    /// - Returns: `overlay` を重ねた ``OverlayView``。
    public func overlay<Overlay: View>(
        _ overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> OverlayView<Self, Overlay> {
        OverlayView(content: self, overlay: overlay, horizontal: horizontal, vertical: vertical)
    }

    /// 画面全体を基準にして、上へ ``View`` を重ねる。
    ///
    /// - Parameters:
    ///   - overlay: 上へ重ねる ``View``。
    ///   - horizontal: `overlay` を画面の横方向で寄せる向き。
    ///   - vertical: `overlay` を画面の縦方向で寄せる向き。
    /// - Returns: 画面全体を基準に `overlay` を重ねた ``ScreenOverlayView``。
    /// - Note: `overlay` が後から描かれる ``View`` に隠れないよう、``ScreenOverlayView`` を、``Application`` が最初にメソッドを呼び出す ``View`` にする（``TerminalApp/body`` がこのメソッドの戻り値を返すようにする）。
    public func screenOverlay<Overlay: View>(
        _ overlay: Overlay,
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> ScreenOverlayView<Self, Overlay> {
        ScreenOverlayView(content: self, overlay: overlay, horizontal: horizontal, vertical: vertical)
    }
}
