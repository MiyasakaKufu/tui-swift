/// 文字列を表示するビュー。
public struct Text: View {
    public var content: String
    public var style: Style
    public var wrap: WrapMode
    public var alignment: HorizontalAlignment

    public init(
        _ content: String,
        style: Style = .plain,
        wrap: WrapMode = .truncate,
        alignment: HorizontalAlignment = .leading
    ) {
        self.content = content
        self.style = style
        self.wrap = wrap
        self.alignment = alignment
    }

    public func sizeThatFits(_ proposal: Size) -> Size {
        let lines = TextWrapping.wrap(content, width: proposal.width, mode: wrap)
        let width = lines.reduce(0) { max($0, DisplayWidth.width(of: $1)) }
        return Size(width: min(width, proposal.width), height: lines.count)
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        let lines = TextWrapping.wrap(content, width: rect.width, mode: wrap)
        buffer.write(lines: Array(lines.prefix(rect.height)), in: rect, style: style, alignment: alignment)
    }

    // MARK: - 見た目の調整

    public func styled(_ style: Style) -> Text {
        var copy = self
        copy.style = style
        return copy
    }

    public func foreground(_ color: Color) -> Text {
        var copy = self
        copy.style.foreground = color
        return copy
    }

    public func background(_ color: Color) -> Text {
        var copy = self
        copy.style.background = color
        return copy
    }

    public func attributes(_ attributes: TextAttributes) -> Text {
        var copy = self
        copy.style.attributes.formUnion(attributes)
        return copy
    }

    public func bold() -> Text { attributes(.bold) }
    public func dim() -> Text { attributes(.dim) }
    public func italic() -> Text { attributes(.italic) }
    public func underline() -> Text { attributes(.underline) }
    public func reverse() -> Text { attributes(.reverse) }

    public func wrapped(_ mode: WrapMode) -> Text {
        var copy = self
        copy.wrap = mode
        return copy
    }

    public func aligned(_ alignment: HorizontalAlignment) -> Text {
        var copy = self
        copy.alignment = alignment
        return copy
    }
}
