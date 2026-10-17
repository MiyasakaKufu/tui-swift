/// 文字列を表示する ``View``。
///
/// 文字色は、`Text.foregroundStyle(_: Color)` などで決めていなければ、外側の `View.foregroundStyle(_: Color)` などで決めた primary の段になる。背景色は、外側の ``View/background(_:)`` で塗った色になる。
public struct Text: PrimitiveView {
    /// 表示する文字列。
    public var content: String
    /// 文字装飾。
    public var attributes: TextAttributes
    /// 折り返しの方法。
    public var wrap: WrapMode
    /// 行の水平方向の揃え。
    public var alignment: HorizontalAlignment
    /// タブストップの間隔（``Cell`` の数）。
    ///
    /// タブは、``Text/content`` を改行で区切った行の先頭から（折り返す前に）数えた ``Cell`` の数が、次にこの値の倍数になる位置まで空白で埋められる。0 以下なら、タブは取り除かれる。
    public var tabSize: Int
    /// `Text.foregroundStyle(_: Color)` などで決めた文字色。`nil` なら外側で決めた primary の段。
    var foreground: ForegroundStyleValue?

    /// 文字列と見た目を指定して ``Text`` を作る。
    ///
    /// - Parameters:
    ///   - content: 表示する文字列。
    ///   - wrap: 折り返しの方法。
    ///   - alignment: 行の水平方向の揃え。
    ///   - tabSize: タブストップの間隔。
    public init(
        _ content: String,
        wrap: WrapMode = .truncate,
        alignment: HorizontalAlignment = .leading,
        tabSize: Int = TabExpansion.defaultSize
    ) {
        self.content = content
        self.attributes = []
        self.wrap = wrap
        self.alignment = alignment
        self.tabSize = tabSize
    }

    /// 折り返した行を収めるサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: ``RenderContext/ambiguousWidth`` を取得するための ``RenderContext``。
    /// - Returns: 最も長い行の幅と、折り返した行数から決まるサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let ambiguous = context.ambiguousWidth
        let lines = TextWrapping.wrap(
            content, width: proposal.width, mode: wrap, tabSize: tabSize, ambiguous: ambiguous
        )
        let width = lines.reduce(0) { max($0, DisplayWidth.width(of: $1, ambiguous: ambiguous)) }
        return Size(width: min(width, proposal.width), height: lines.count)
    }

    /// 折り返した各行を `rect` の中へ描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。高さに収まらない行は描画されない。
    ///   - context: ``RenderContext/ambiguousWidth`` を取得し、文字色と背景色を決めるための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        context.recordHitRegion(rect)
        let lines = TextWrapping.wrap(
            content, width: rect.width, mode: wrap, tabSize: tabSize, ambiguous: context.ambiguousWidth
        )
        var style = context.colors.style(foreground ?? .hierarchical(.primary))
        style.attributes.formUnion(attributes)
        // ここでタブを展開してはいけない。`TextWrapping.wrap` が展開した行が二重に広がる。
        buffer.write(lines: Array(lines.prefix(rect.height)), in: rect, style: style, alignment: alignment)
    }

    // MARK: - 見た目の調整

    /// 文字色を `style` にした複製。
    ///
    /// - Parameters:
    ///   - style: 文字色。
    /// - Returns: 文字色を差し替えた複製。
    public func foregroundStyle(_ style: Color) -> Text {
        var copy = self
        copy.foreground = .color(style)
        return copy
    }

    /// 文字色を、外側で決めた文字色の `style` の段にした複製。
    ///
    /// - Parameters:
    ///   - style: 外側で決めた文字色のうち、使う段。
    /// - Returns: 文字色を差し替えた複製。
    public func foregroundStyle(_ style: HierarchicalShapeStyle) -> Text {
        var copy = self
        copy.foreground = .hierarchical(style)
        return copy
    }

    /// 装飾を足した複製。
    ///
    /// - Parameters:
    ///   - attributes: 足す装飾。
    /// - Returns: 装飾を足した複製。
    public func attributes(_ attributes: TextAttributes) -> Text {
        var copy = self
        copy.attributes.formUnion(attributes)
        return copy
    }

    /// 太字にした複製。
    ///
    /// - Returns: 太字を足した複製。
    public func bold() -> Text { attributes(.bold) }

    /// 減光した複製。
    ///
    /// - Returns: 減光を足した複製。
    public func dim() -> Text { attributes(.dim) }

    /// 斜体にした複製。
    ///
    /// - Returns: 斜体を足した複製。
    public func italic() -> Text { attributes(.italic) }

    /// 下線を引いた複製。
    ///
    /// - Returns: 下線を足した複製。
    public func underline() -> Text { attributes(.underline) }

    /// 文字色と背景色を反転した複製。
    ///
    /// - Returns: 反転を足した複製。
    public func reverse() -> Text { attributes(.reverse) }

    /// 折り返しの方法を差し替えた複製。
    ///
    /// - Parameters:
    ///   - mode: 新しい折り返しの方法。
    /// - Returns: 折り返しの方法を差し替えた複製。
    public func wrapped(_ mode: WrapMode) -> Text {
        var copy = self
        copy.wrap = mode
        return copy
    }

    /// 行の揃えを差し替えた複製。
    ///
    /// - Parameters:
    ///   - alignment: 新しい揃え。
    /// - Returns: 行の揃えを差し替えた複製。
    public func aligned(_ alignment: HorizontalAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }

    /// タブストップの間隔を変えた複製。
    ///
    /// - Parameters:
    ///   - size: タブストップの間隔。0 を渡すとタブを取り除く。
    /// - Returns: タブストップの間隔を変えた複製。
    public func tabStops(every size: Int) -> Text {
        var copy = self
        copy.tabSize = size
        return copy
    }

    /// ``RenderContext`` のメソッドに ``View`` を渡さないので、何もしない。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {}
}
