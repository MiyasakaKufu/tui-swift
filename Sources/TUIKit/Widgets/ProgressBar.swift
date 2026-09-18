/// 進捗バー。
public struct ProgressBar: View {
    /// 0.0 〜 1.0 に丸められた進捗。
    public var progress: Double
    public var filledCharacter: Character
    public var emptyCharacter: Character
    public var filledStyle: Style
    public var emptyStyle: Style
    /// 右端に "42%" のような表示を付ける。
    public var showsPercentage: Bool

    public init(
        value: Double,
        total: Double = 1.0,
        filledCharacter: Character = "█",
        emptyCharacter: Character = "░",
        filledStyle: Style = Style(foreground: .green),
        emptyStyle: Style = Style(foreground: .brightBlack),
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

    /// 実際に描画へ使う記号。
    ///
    /// 既定の `█` は East Asian Width が Ambiguous なので、`DisplayWidth.ambiguousWidth`
    /// が `.wide` のときは 2 桁になりバーが崩れる。1 桁に収まらない記号は ASCII へ落とす。
    var effectiveFilledCharacter: Character {
        DisplayWidth.width(of: filledCharacter) == 1 ? filledCharacter : "#"
    }

    /// 実際に描画へ使う未達部分の記号。`effectiveFilledCharacter` と同じ理由で置き換える。
    var effectiveEmptyCharacter: Character {
        DisplayWidth.width(of: emptyCharacter) == 1 ? emptyCharacter : "-"
    }

    public var layoutTraits: LayoutTraits { LayoutTraits(horizontalFlex: 1, verticalFlex: 0) }

    public func sizeThatFits(_ proposal: Size) -> Size {
        Size(width: proposal.width, height: min(1, proposal.height))
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard rect.width > 0, rect.height > 0 else { return }

        var barWidth = rect.width
        var suffix = ""
        if showsPercentage {
            suffix = " " + String(Int((progress * 100).rounded())) + "%"
            barWidth = max(0, rect.width - DisplayWidth.width(of: suffix))
        }

        let filled = Int((Double(barWidth) * progress).rounded())
        let filledSymbol = effectiveFilledCharacter
        let emptySymbol = effectiveEmptyCharacter
        for offset in 0..<barWidth {
            let isFilled = offset < filled
            buffer[rect.minX + offset, rect.minY] = Cell(
                character: isFilled ? filledSymbol : emptySymbol,
                style: isFilled ? filledStyle : emptyStyle
            )
        }

        if !suffix.isEmpty {
            buffer.write(
                suffix,
                at: Point(x: rect.minX + barWidth, y: rect.minY),
                style: emptyStyle,
                clippedTo: rect
            )
        }
    }
}
