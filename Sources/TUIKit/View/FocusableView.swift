/// 内容が占める矩形を、フォーカスの対象として登録するビュー。
public struct FocusableView<Content: View>: View {
    /// 登録する矩形に描く内容。
    public var content: Content
    /// 矩形に結び付けるフォーカスの対象。
    public var target: FocusTarget
    /// 登録先。
    public var manager: FocusManager

    /// 内容と、それに結び付けるフォーカスの対象を指定して作る。
    ///
    /// - Parameters:
    ///   - content: 登録する矩形に描く内容。
    ///   - target: 矩形に結び付けるフォーカスの対象。
    ///   - manager: 登録先。
    public init(content: Content, target: FocusTarget, manager: FocusManager) {
        self.content = content
        self.target = target
        self.manager = manager
    }

    /// 内容と同じ。
    public var layoutTraits: LayoutTraits { content.layoutTraits }

    /// 内容の希望サイズをそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    /// - Returns: 内容の希望サイズ。
    public func sizeThatFits(_ proposal: Size) -> Size {
        content.sizeThatFits(proposal)
    }

    /// 矩形を登録してから内容を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    /// - Postcondition: この描画の登録に `target` が加わり、`rect` がマウスの当たり判定になる。
    public func render(into buffer: inout Buffer, rect: Rect) {
        manager.register(target, rect: rect)
        content.render(into: &buffer, rect: rect)
    }
}

extension View {
    /// フォーカスを受け取れるようにする。
    ///
    /// - Parameters:
    ///   - target: このビューに結び付けるフォーカスの対象。
    ///   - manager: 登録先。
    /// - Returns: 描画のたびに矩形を登録するビュー。
    /// - Note: マウスの当たり判定に使うのは、このビューが占める矩形。枠線や余白の上の
    ///   クリックでもフォーカスを移したいなら、`.border(_:style:title:titleStyle:)` や
    ///   `.padding(_:)` の外側で呼ぶ。
    public func focusable(_ target: FocusTarget, in manager: FocusManager) -> FocusableView<Self> {
        FocusableView(content: self, target: target, manager: manager)
    }
}
