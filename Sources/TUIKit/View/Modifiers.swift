/// 内容の周囲に余白を取るビュー。
public struct PaddingView: View {
    public var content: any View
    public var insets: EdgeInsets

    public init(content: any View, insets: EdgeInsets) {
        self.content = content
        self.insets = insets
    }

    public var layoutTraits: LayoutTraits { content.layoutTraits }

    public func sizeThatFits(_ proposal: Size) -> Size {
        let inner = Size(
            width: proposal.width - insets.horizontal,
            height: proposal.height - insets.vertical
        )
        let desired = content.sizeThatFits(inner)
        return Size(
            width: min(desired.width + insets.horizontal, proposal.width),
            height: min(desired.height + insets.vertical, proposal.height)
        )
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        let inner = rect.inset(by: insets)
        guard !inner.isEmpty else { return }
        content.render(into: &buffer, rect: inner)
    }
}

/// 内容を枠線で囲むビュー。
public struct BorderView: View {
    public var content: any View
    public var borderStyle: BorderStyle
    public var style: Style
    public var title: String?
    public var titleStyle: Style?

    public init(
        content: any View,
        borderStyle: BorderStyle = .single,
        style: Style = .plain,
        title: String? = nil,
        titleStyle: Style? = nil
    ) {
        self.content = content
        self.borderStyle = borderStyle
        self.style = style
        self.title = title
        self.titleStyle = titleStyle
    }

    public var layoutTraits: LayoutTraits { content.layoutTraits }

    public func sizeThatFits(_ proposal: Size) -> Size {
        let inner = Size(width: proposal.width - 2, height: proposal.height - 2)
        let desired = content.sizeThatFits(inner)
        var width = desired.width + 2
        if let titleText = title {
            width = max(width, DisplayWidth.width(of: titleText) + 4)
        }
        return Size(
            width: min(width, proposal.width),
            height: min(desired.height + 2, proposal.height)
        )
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        drawFrame(into: &buffer, rect: rect)
        let inner = rect.inset(by: 1)
        if !inner.isEmpty {
            content.render(into: &buffer, rect: inner)
        }
    }

    private func drawFrame(into buffer: inout Buffer, rect: Rect) {
        let top = rect.minY
        let bottom = rect.maxY - 1
        let left = rect.minX
        let right = rect.maxX - 1

        buffer[left, top] = Cell(character: borderStyle.topLeft, style: style)
        buffer[right, top] = Cell(character: borderStyle.topRight, style: style)
        buffer[left, bottom] = Cell(character: borderStyle.bottomLeft, style: style)
        buffer[right, bottom] = Cell(character: borderStyle.bottomRight, style: style)

        if right > left + 1 {
            for x in (left + 1)...(right - 1) {
                buffer[x, top] = Cell(character: borderStyle.top, style: style)
                buffer[x, bottom] = Cell(character: borderStyle.bottom, style: style)
            }
        }
        if bottom > top + 1 {
            for y in (top + 1)...(bottom - 1) {
                buffer[left, y] = Cell(character: borderStyle.left, style: style)
                buffer[right, y] = Cell(character: borderStyle.right, style: style)
            }
        }

        if let titleText = title, rect.width > 4 {
            let available = rect.width - 4
            let trimmed = DisplayWidth.truncate(" " + titleText + " ", to: available + 2)
            buffer.write(
                trimmed,
                at: Point(x: left + 1, y: top),
                style: titleStyle ?? style,
                clippedTo: Rect(x: left + 1, y: top, width: rect.width - 2, height: 1)
            )
        }
    }
}

/// 背景を塗るビュー。
public struct BackgroundView: View {
    public var content: any View
    public var style: Style

    public init(content: any View, style: Style) {
        self.content = content
        self.style = style
    }

    public var layoutTraits: LayoutTraits { content.layoutTraits }

    public func sizeThatFits(_ proposal: Size) -> Size {
        content.sizeThatFits(proposal)
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        buffer.fill(rect, style: style)
        content.render(into: &buffer, rect: rect)
    }
}

/// サイズを固定するビュー。
public struct FrameView: View {
    public var content: any View
    public var width: Int?
    public var height: Int?
    public var horizontalAlignment: HorizontalAlignment
    public var verticalAlignment: VerticalAlignment

    public init(
        content: any View,
        width: Int? = nil,
        height: Int? = nil,
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .top
    ) {
        self.content = content
        self.width = width
        self.height = height
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
    }

    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: width == nil ? content.layoutTraits.horizontalFlex : 0,
            verticalFlex: height == nil ? content.layoutTraits.verticalFlex : 0
        )
    }

    public func sizeThatFits(_ proposal: Size) -> Size {
        let desired = content.sizeThatFits(proposal)
        return Size(
            width: min(width ?? desired.width, proposal.width),
            height: min(height ?? desired.height, proposal.height)
        )
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        let contentWidth = min(width ?? rect.width, rect.width)
        let contentHeight = min(height ?? rect.height, rect.height)
        let x = rect.minX + horizontalAlignment.offset(content: contentWidth, available: rect.width)
        let y = rect.minY + verticalAlignment.offset(content: contentHeight, available: rect.height)
        content.render(into: &buffer, rect: Rect(x: x, y: y, width: contentWidth, height: contentHeight))
    }
}

/// 余白の分配ルールだけを差し替えるビュー。
public struct FlexibleView: View {
    public var content: any View
    public var traits: LayoutTraits

    public init(content: any View, traits: LayoutTraits) {
        self.content = content
        self.traits = traits
    }

    public var layoutTraits: LayoutTraits { traits }

    public func sizeThatFits(_ proposal: Size) -> Size {
        content.sizeThatFits(proposal)
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        content.render(into: &buffer, rect: rect)
    }
}

/// 与えられた領域の中で内容を寄せるビュー。
public struct AlignedView: View {
    public var content: any View
    public var horizontal: HorizontalAlignment
    public var vertical: VerticalAlignment

    public init(content: any View, horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.content = content
        self.horizontal = horizontal
        self.vertical = vertical
    }

    public var layoutTraits: LayoutTraits { .flexible }

    public func sizeThatFits(_ proposal: Size) -> Size { proposal }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }
        let desired = content.sizeThatFits(rect.size).clamped(to: rect.size)
        let x = rect.minX + horizontal.offset(content: desired.width, available: rect.width)
        let y = rect.minY + vertical.offset(content: desired.height, available: rect.height)
        content.render(into: &buffer, rect: Rect(origin: Point(x: x, y: y), size: desired))
    }
}

extension View {
    /// 周囲に余白を取る。
    public func padding(_ insets: EdgeInsets) -> PaddingView {
        PaddingView(content: self, insets: insets)
    }

    public func padding(_ amount: Int) -> PaddingView {
        PaddingView(content: self, insets: EdgeInsets(all: amount))
    }

    public func padding(horizontal: Int = 0, vertical: Int = 0) -> PaddingView {
        PaddingView(content: self, insets: EdgeInsets(horizontal: horizontal, vertical: vertical))
    }

    /// 枠線で囲む。
    public func border(
        _ borderStyle: BorderStyle = .single,
        style: Style = .plain,
        title: String? = nil,
        titleStyle: Style? = nil
    ) -> BorderView {
        BorderView(content: self, borderStyle: borderStyle, style: style, title: title, titleStyle: titleStyle)
    }

    /// 背景色を塗る。
    public func background(_ color: Color) -> BackgroundView {
        BackgroundView(content: self, style: Style(background: color))
    }

    public func background(style: Style) -> BackgroundView {
        BackgroundView(content: self, style: style)
    }

    /// 幅・高さを固定する。
    public func frame(
        width: Int? = nil,
        height: Int? = nil,
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .top
    ) -> FrameView {
        FrameView(
            content: self,
            width: width,
            height: height,
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment
        )
    }

    /// 余った領域を引き取るようにする。
    public func flexible(horizontal: Int = 1, vertical: Int = 1) -> FlexibleView {
        FlexibleView(
            content: self,
            traits: LayoutTraits(horizontalFlex: horizontal, verticalFlex: vertical)
        )
    }

    /// 領域いっぱいを受け取り、その中で内容を寄せる。
    public func aligned(
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> AlignedView {
        AlignedView(content: self, horizontal: horizontal, vertical: vertical)
    }
}
