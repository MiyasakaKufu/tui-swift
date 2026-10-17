/// ``ForegroundStyleView/content`` の文字色を決める ``View``。`View.foregroundStyle(_: Color)`・`View.foregroundStyle(_: HierarchicalShapeStyle)`・`View.foregroundStyle(_:_:)` で作る。
///
/// ``ForegroundStyleView/content`` と、その内側の ``Text``・``ListView`` などの文字は、もっと内側で文字色を決めていなければ、この文字色で描かれる。
public struct ForegroundStyleView<Content: View>: PrimitiveView {
    /// 文字色を決める範囲の ``View``。
    public var content: Content
    /// プライマリレベルにする文字色。
    let primary: ForegroundStyleValue
    /// セカンダリレベルにする文字色。`nil` ならプライマリレベルから決まる。
    let secondary: Color?

    /// ``ForegroundStyleView`` を作る。
    ///
    /// - Parameters:
    ///   - content: 文字色を決める範囲の ``View``。
    ///   - primary: プライマリレベルにする文字色。
    ///   - secondary: セカンダリレベルにする文字色。`nil` ならプライマリレベルから決まる。
    init(content: Content, primary: ForegroundStyleValue, secondary: Color?) {
        self.content = content
        self.primary = primary
        self.secondary = secondary
    }

    /// ``ForegroundStyleView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``ForegroundStyleView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// ``ForegroundStyleView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``ForegroundStyleView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// 文字色を決め直してから ``ForegroundStyleView/content`` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context
            .withColors { $0.setForeground(primary, secondary: secondary) }
            .render(content, index: 0, into: &buffer, rect: rect)
    }

    /// ``ForegroundStyleView/content`` を、`index:` 引数を 0 として `visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(content, index: 0)
    }
}

/// ``TintView/content`` のティントカラーを決める ``View``。``View/tint(_:)`` で作る。
public struct TintView<Content: View>: PrimitiveView {
    /// ティントカラーを決める範囲の ``View``。
    public var content: Content
    /// ティントカラー。`nil` ならプライマリレベルの文字色。
    public var tint: Color?

    /// ``TintView`` を作る。
    ///
    /// - Parameters:
    ///   - content: ティントカラーを決める範囲の ``View``。
    ///   - tint: ティントカラー。`nil` ならプライマリレベルの文字色。
    init(content: Content, tint: Color?) {
        self.content = content
        self.tint = tint
    }

    /// ``TintView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``TintView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// ``TintView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``TintView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// ティントカラーを決め直してから ``TintView/content`` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context
            .withColors { $0.tint = tint }
            .render(content, index: 0, into: &buffer, rect: rect)
    }

    /// ``TintView/content`` を、`index:` 引数を 0 として `visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(content, index: 0)
    }
}

extension View {
    /// この ``View`` と、その内側の前景スタイルを `style` にする。
    ///
    /// セカンダリレベルは、`style` に ``TextAttributes/dim`` を足したものになる。
    ///
    /// - Parameters:
    ///   - style: プライマリレベルにする文字色。
    /// - Returns: この ``View`` を ``ForegroundStyleView/content`` にした ``ForegroundStyleView``。
    public func foregroundStyle(_ style: Color) -> ForegroundStyleView<Self> {
        ForegroundStyleView(content: self, primary: .color(style), secondary: nil)
    }

    /// この ``View`` と、その内側の前景スタイルを、この ``View`` を内側に含む ``View``が決めた前景スタイルの `style` のレベルにする。
    ///
    /// - Parameters:
    ///   - style: この ``View`` を内側に含む ``View``が決めた前景スタイルのうち、プライマリレベルにするレベル。
    /// - Returns: この ``View`` を ``ForegroundStyleView/content`` にした ``ForegroundStyleView``。
    public func foregroundStyle(_ style: HierarchicalShapeStyle) -> ForegroundStyleView<Self> {
        ForegroundStyleView(content: self, primary: .hierarchical(style), secondary: nil)
    }

    /// この ``View`` と、その内側の前景スタイルのプライマリレベルとセカンダリレベルを決める。
    ///
    /// - Parameters:
    ///   - primary: プライマリレベルにする文字色。
    ///   - secondary: セカンダリレベルにする文字色。
    /// - Returns: この ``View`` を ``ForegroundStyleView/content`` にした ``ForegroundStyleView``。
    public func foregroundStyle(_ primary: Color, _ secondary: Color) -> ForegroundStyleView<Self> {
        ForegroundStyleView(content: self, primary: .color(primary), secondary: secondary)
    }

    /// この ``View`` と、その内側のティントカラーを `tint` にする。
    ///
    /// ティントカラーを使うのは、``ProgressBar`` の進んだ部分と、``ListView`` の選択行。``ListView`` は、ティントカラーを文字色にして反転した ``Style`` で選択行を描く。
    ///
    /// - Parameters:
    ///   - tint: ティントカラー。`nil` ならプライマリレベルの文字色。
    /// - Returns: この ``View`` を ``TintView/content`` にした ``TintView``。
    public func tint(_ tint: Color?) -> TintView<Self> {
        TintView(content: self, tint: tint)
    }
}
