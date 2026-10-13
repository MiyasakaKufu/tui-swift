/// 進捗バー。
public struct ProgressBar: PrimitiveView {
    /// 0.0 〜 1.0 に丸められた進捗。
    public var progress: Double
    /// 進んだ部分を埋める文字。
    public var filledCharacter: Character
    /// まだ進んでいない部分を埋める文字。
    public var emptyCharacter: Character
    /// 進んだ部分のスタイル。`nil` なら ``RenderContext/theme`` の ``Theme/accent``。
    public var filledStyle: Style?
    /// まだ進んでいない部分と百分率のスタイル。`nil` なら ``RenderContext/theme`` の ``Theme/secondaryText``。
    public var emptyStyle: Style?
    /// 右端に "42%" のような表示を付ける。
    public var showsPercentage: Bool

    /// 進捗と見た目を指定してバーを作る。
    ///
    /// - Parameters:
    ///   - value: 現在の値。
    ///   - total: 全体の値。0 以下なら進捗を 0 として扱う。
    ///   - filledCharacter: 進んだ部分を埋める文字。
    ///   - emptyCharacter: まだ進んでいない部分を埋める文字。
    ///   - filledStyle: 進んだ部分のスタイル。`nil` なら ``RenderContext/theme`` の ``Theme/accent``。
    ///   - emptyStyle: まだ進んでいない部分と百分率のスタイル。`nil` なら ``RenderContext/theme`` の ``Theme/secondaryText``。
    ///   - showsPercentage: 右端に百分率を付けるか。
    /// - Postcondition: `progress` は 0.0 〜 1.0 に丸められる。
    public init(
        value: Double,
        total: Double = 1.0,
        filledCharacter: Character = "█",
        emptyCharacter: Character = "░",
        filledStyle: Style? = nil,
        emptyStyle: Style? = nil,
        showsPercentage: Bool = false
    ) {
        let ratio = total > 0 ? value / total : 0
        self.progress = min(1.0, max(0.0, ratio))
        self.filledCharacter = filledCharacter
        self.emptyCharacter = emptyCharacter
        self.filledStyle = filledStyle
        self.emptyStyle = emptyStyle
        self.showsPercentage = showsPercentage
    }

    /// ``LayoutTraits/horizontalFlex`` だけを 1 にした ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``LayoutTraits/horizontalFlex`` が 1、``LayoutTraits/verticalFlex`` が 0 の ``LayoutTraits``。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        LayoutTraits(horizontalFlex: 1, verticalFlex: 0)
    }

    /// `proposal` の幅いっぱいで、高さが 1 を超えない ``Size`` を返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: `proposal` の幅と、1 と `proposal.height` の小さい方を高さにした ``Size``。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: proposal.width, height: min(1, proposal.height))
    }

    /// バーと、必要なら百分率を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。使うのは最初の 1 行だけ。
    ///   - context: 文字列の幅を測るときに ``RenderContext/ambiguousWidth`` を読み、``RenderContext/theme`` を取得する ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        context.recordHitRegion(rect)

        var barWidth = rect.width
        var suffix = ""
        if showsPercentage {
            suffix = " " + String(Int((progress * 100).rounded())) + "%"
            barWidth = max(0, rect.width - DisplayWidth.width(of: suffix, ambiguous: context.ambiguousWidth))
        }

        let filledStyle = filledStyle ?? context.theme.accent
        let emptyStyle = emptyStyle ?? context.theme.secondaryText
        let filled = Int((Double(barWidth) * progress).rounded())
        buffer.fill(
            Rect(x: rect.minX, y: rect.minY, width: filled, height: 1),
            repeating: filledCharacter,
            style: filledStyle
        )
        buffer.fill(
            Rect(x: rect.minX + filled, y: rect.minY, width: barWidth - filled, height: 1),
            repeating: emptyCharacter,
            style: emptyStyle
        )

        if !suffix.isEmpty {
            buffer.write(
                suffix,
                at: Point(x: rect.minX + barWidth, y: rect.minY),
                style: emptyStyle,
                clippedTo: rect
            )
        }
    }

    /// ``RenderContext`` のメソッドに ``View`` を渡さないので、何もしない。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {}
}
