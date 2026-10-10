/// 文字列を表示する `View`。
public struct Text: PrimitiveView {
    /// 表示する文字列。
    public var content: String
    /// 文字のスタイル。
    public var style: Style
    /// 折り返しの方法。
    public var wrap: WrapMode
    /// 行の水平方向の揃え。
    public var alignment: HorizontalAlignment
    /// タブストップの間隔（`Cell` の数）。
    ///
    /// タブは、`content` を改行で区切った行の先頭から（折り返す前に）数えた `Cell` の数が、次にこの値の倍数になる
    /// 位置まで空白で埋められる。0 以下なら、タブは取り除かれる。
    public var tabSize: Int

    /// 文字列と見た目を指定して `Text` を作る。
    ///
    /// - Parameters:
    ///   - content: 表示する文字列。
    ///   - style: 文字のスタイル。
    ///   - wrap: 折り返しの方法。
    ///   - alignment: 行の水平方向の揃え。
    ///   - tabSize: タブストップの間隔。
    public init(
        _ content: String,
        style: Style = .plain,
        wrap: WrapMode = .truncate,
        alignment: HorizontalAlignment = .leading,
        tabSize: Int = TabExpansion.defaultSize
    ) {
        self.content = content
        self.style = style
        self.wrap = wrap
        self.alignment = alignment
        self.tabSize = tabSize
    }

    /// 折り返した行を収めるサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: `RenderContext.ambiguousWidth` を取得するための `RenderContext`。
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
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。高さに収まらない行は描画されない。
    ///   - context: `RenderContext.ambiguousWidth` を取得するための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        let lines = TextWrapping.wrap(
            content, width: rect.width, mode: wrap, tabSize: tabSize, ambiguous: context.ambiguousWidth
        )
        // ここでタブを展開してはいけない。`TextWrapping.wrap` が展開した行が二重に広がる。
        buffer.write(lines: Array(lines.prefix(rect.height)), in: rect, style: style, alignment: alignment)
    }

    // MARK: - 見た目の調整

    /// スタイルを差し替えた複製。
    ///
    /// - Parameters:
    ///   - style: 新しいスタイル。
    /// - Returns: スタイルを差し替えた複製。
    public func styled(_ style: Style) -> Text {
        var copy = self
        copy.style = style
        return copy
    }

    /// 文字色を差し替えた複製。
    ///
    /// - Parameters:
    ///   - color: 新しい文字色。
    /// - Returns: 文字色を差し替えた複製。
    public func foreground(_ color: Color) -> Text {
        var copy = self
        copy.style.foreground = color
        return copy
    }

    /// 背景色を差し替えた複製。
    ///
    /// - Parameters:
    ///   - color: 新しい背景色。
    /// - Returns: 背景色を差し替えた複製。
    public func background(_ color: Color) -> Text {
        var copy = self
        copy.style.background = color
        return copy
    }

    /// 装飾を足した複製。
    ///
    /// - Parameters:
    ///   - attributes: 足す装飾。
    /// - Returns: 装飾を足した複製。
    public func attributes(_ attributes: TextAttributes) -> Text {
        var copy = self
        copy.style.attributes.formUnion(attributes)
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
}
