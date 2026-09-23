/// 内容の周囲に余白を取るビュー。
public struct PaddingView<Content: View>: View {
    /// 余白の内側に置く内容。
    public var content: Content
    /// 内容の周囲に取る余白。
    public var insets: EdgeInsets

    /// 内容と余白を指定して作る。
    ///
    /// - Parameters:
    ///   - content: 余白の内側に置く内容。
    ///   - insets: 内容の周囲に取る余白。
    public init(content: Content, insets: EdgeInsets) {
        self.content = content
        self.insets = insets
    }

    /// 内容と同じ。
    public var layoutTraits: LayoutTraits { content.layoutTraits }

    /// 余白の分を足した希望サイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズに余白を足したサイズ。`proposal` は超えない。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let inner = Size(
            width: proposal.width - insets.horizontal,
            height: proposal.height - insets.vertical
        )
        let desired = context.sizeThatFits(of: content, index: 0, proposal: inner)
        return Size(
            width: min(desired.width + insets.horizontal, proposal.width),
            height: min(desired.height + insets.vertical, proposal.height)
        )
    }

    /// 余白の内側へ内容を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 余白を含めた矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        let inner = rect.inset(by: insets)
        guard !inner.isEmpty else { return }
        context.render(content, index: 0, into: &buffer, rect: inner)
    }
}

/// 内容を枠線で囲むビュー。
public struct BorderView<Content: View>: View {
    /// 枠線の内側に置く内容。
    public var content: Content
    /// 枠線に使う文字の組み合わせ。
    public var borderStyle: BorderStyle
    /// 枠線のスタイル。
    public var style: Style
    /// 上辺に重ねる見出し。`nil` なら見出しを出さない。
    public var title: String?
    /// 見出しのスタイル。`nil` なら枠線と同じスタイル。
    public var titleStyle: Style?

    /// 内容と枠線の見た目を指定して作る。
    ///
    /// - Parameters:
    ///   - content: 枠線の内側に置く内容。
    ///   - borderStyle: 枠線に使う文字の組み合わせ。
    ///   - style: 枠線のスタイル。
    ///   - title: 上辺に重ねる見出し。
    ///   - titleStyle: 見出しのスタイル。`nil` なら枠線と同じスタイル。
    public init(
        content: Content,
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

    /// 内容と同じ。
    public var layoutTraits: LayoutTraits { content.layoutTraits }

    /// 枠線の 2 桁・2 行を足した希望サイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズに枠線を足したサイズ。見出しがあれば、それが収まる幅まで広げる。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let inner = Size(width: proposal.width - 2, height: proposal.height - 2)
        let desired = context.sizeThatFits(of: content, index: 0, proposal: inner)
        var width = desired.width + 2
        if let titleText = title {
            width = max(width, DisplayWidth.width(of: TabExpansion.expand(titleText)) + 4)
        }
        return Size(
            width: min(width, proposal.width),
            height: min(desired.height + 2, proposal.height)
        )
    }

    /// 枠線と見出しを描き、内側へ内容を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 枠線を含めた矩形。幅・高さが 2 未満なら何も描かない。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        drawFrame(into: &buffer, rect: rect)
        let inner = rect.inset(by: 1)
        if !inner.isEmpty {
            context.render(content, index: 0, into: &buffer, rect: inner)
        }
    }

    /// 実際に枠として描く文字の組み合わせ。
    ///
    /// `borderStyle` が 1 桁に収まらないときは `.ascii` になる。
    var effectiveBorderStyle: BorderStyle {
        borderStyle.fitsInSingleColumn ? borderStyle : .ascii
    }

    /// 枠線と見出しを描く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 枠線を含めた矩形。
    private func drawFrame(into buffer: inout Buffer, rect: Rect) {
        let border = effectiveBorderStyle
        let top = rect.minY
        let bottom = rect.maxY - 1
        let left = rect.minX
        let right = rect.maxX - 1

        buffer[left, top] = Cell(character: border.topLeft, style: style)
        buffer[right, top] = Cell(character: border.topRight, style: style)
        buffer[left, bottom] = Cell(character: border.bottomLeft, style: style)
        buffer[right, bottom] = Cell(character: border.bottomRight, style: style)

        if right > left + 1 {
            for x in (left + 1)...(right - 1) {
                buffer[x, top] = Cell(character: border.top, style: style)
                buffer[x, bottom] = Cell(character: border.bottom, style: style)
            }
        }
        if bottom > top + 1 {
            for y in (top + 1)...(bottom - 1) {
                buffer[left, y] = Cell(character: border.left, style: style)
                buffer[right, y] = Cell(character: border.right, style: style)
            }
        }

        if let titleText = title, rect.width > 4 {
            let available = rect.width - 4
            // 幅で切り詰める前に展開しないと、タブの分だけ桁数の計算がずれる。
            let expanded = TabExpansion.expand(" " + titleText + " ")
            let trimmed = DisplayWidth.truncate(expanded, to: available + 2)
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
public struct BackgroundView<Content: View>: View {
    /// 背景の上に置く内容。
    public var content: Content
    /// 背景を塗るスタイル。
    public var style: Style

    /// 内容と背景のスタイルを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 背景の上に置く内容。
    ///   - style: 背景を塗るスタイル。
    public init(content: Content, style: Style) {
        self.content = content
        self.style = style
    }

    /// 内容と同じ。
    public var layoutTraits: LayoutTraits { content.layoutTraits }

    /// 内容の希望サイズをそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// 領域を塗ってから内容を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        buffer.fill(rect, style: style)
        context.render(content, index: 0, into: &buffer, rect: rect)
    }
}

/// サイズを固定するビュー。負の幅・高さは 0 に丸められる。
public struct FrameView<Content: View>: View {
    /// 固定した領域に置く内容。
    public var content: Content
    /// 固定する幅。`nil` なら内容の希望に任せる。負の値は 0 に丸められる。
    public var width: Int? {
        didSet { width = width.map { max(0, $0) } }
    }
    /// 固定する高さ。`nil` なら内容の希望に任せる。負の値は 0 に丸められる。
    public var height: Int? {
        didSet { height = height.map { max(0, $0) } }
    }
    /// 領域の中で内容を横に寄せる向き。
    public var horizontalAlignment: HorizontalAlignment
    /// 領域の中で内容を縦に寄せる向き。
    public var verticalAlignment: VerticalAlignment

    /// 内容と固定するサイズを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 固定した領域に置く内容。
    ///   - width: 固定する幅。`nil` なら内容の希望に任せる。
    ///   - height: 固定する高さ。`nil` なら内容の希望に任せる。
    ///   - horizontalAlignment: 領域の中で内容を横に寄せる向き。
    ///   - verticalAlignment: 領域の中で内容を縦に寄せる向き。
    public init(
        content: Content,
        width: Int? = nil,
        height: Int? = nil,
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .top
    ) {
        self.content = content
        self.width = width.map { max(0, $0) }
        self.height = height.map { max(0, $0) }
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
    }

    /// サイズを固定した方向は伸びず、固定していない方向は内容と同じ。
    public var layoutTraits: LayoutTraits {
        LayoutTraits(
            horizontalFlex: width == nil ? content.layoutTraits.horizontalFlex : 0,
            verticalFlex: height == nil ? content.layoutTraits.verticalFlex : 0
        )
    }

    /// 固定したサイズ、または内容の希望サイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 固定した方向はその値、固定していない方向は内容の希望サイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let desired = context.sizeThatFits(of: content, index: 0, proposal: proposal)
        return Size(
            width: min(width ?? desired.width, proposal.width),
            height: min(height ?? desired.height, proposal.height)
        )
    }

    /// 固定したサイズの領域へ内容を寄せて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        let contentWidth = min(width ?? rect.width, rect.width)
        let contentHeight = min(height ?? rect.height, rect.height)
        let x = rect.minX + horizontalAlignment.offset(content: contentWidth, available: rect.width)
        let y = rect.minY + verticalAlignment.offset(content: contentHeight, available: rect.height)
        let contentRect = Rect(x: x, y: y, width: contentWidth, height: contentHeight)
        context.render(content, index: 0, into: &buffer, rect: contentRect)
    }
}

/// 余白の分配ルールだけを差し替えるビュー。
public struct FlexibleView<Content: View>: View {
    /// 分配ルールを差し替える対象の内容。
    public var content: Content
    /// 内容の代わりに使う、余白の分配に関する性質。
    public var traits: LayoutTraits

    /// 内容と分配ルールを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 分配ルールを差し替える対象の内容。
    ///   - traits: 内容の代わりに使う性質。
    public init(content: Content, traits: LayoutTraits) {
        self.content = content
        self.traits = traits
    }

    /// `traits` に差し替えた性質。
    public var layoutTraits: LayoutTraits { traits }

    /// 内容の希望サイズをそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: 内容の希望サイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// 領域へ内容をそのまま描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(content, index: 0, into: &buffer, rect: rect)
    }
}

/// 与えられた領域の中で内容を寄せるビュー。
public struct AlignedView<Content: View>: View {
    /// 領域の中に寄せて置く内容。
    public var content: Content
    /// 横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// 内容と寄せる向きを指定して作る。
    ///
    /// - Parameters:
    ///   - content: 領域の中に寄せて置く内容。
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    public init(content: Content, horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.content = content
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// 両方向に伸びる。
    public var layoutTraits: LayoutTraits { .flexible }

    /// 提案された領域をそのまま受け取る。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    ///   - context: ライブラリから渡される文脈。
    /// - Returns: `proposal` と同じサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    /// 領域の中で内容を寄せて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    ///   - context: ライブラリから渡される文脈。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        let desired = context.sizeThatFits(of: content, index: 0, proposal: rect.size)
            .clamped(to: rect.size)
        let x = rect.minX + horizontal.offset(content: desired.width, available: rect.width)
        let y = rect.minY + vertical.offset(content: desired.height, available: rect.height)
        context.render(content, index: 0, into: &buffer, rect: Rect(origin: Point(x: x, y: y), size: desired))
    }
}

extension View {
    /// 周囲に余白を取る。
    ///
    /// - Parameters:
    ///   - insets: 四辺に取る余白。
    /// - Returns: 余白で囲んだビュー。
    public func padding(_ insets: EdgeInsets) -> PaddingView<Self> {
        PaddingView(content: self, insets: insets)
    }

    /// 四辺に同じ余白を取る。
    ///
    /// - Parameters:
    ///   - amount: 各辺に取る余白。
    /// - Returns: 余白で囲んだビュー。
    public func padding(_ amount: Int) -> PaddingView<Self> {
        PaddingView(content: self, insets: EdgeInsets(all: amount))
    }

    /// 左右と上下で余白を分けて取る。
    ///
    /// - Parameters:
    ///   - horizontal: 左右の余白。
    ///   - vertical: 上下の余白。
    /// - Returns: 余白で囲んだビュー。
    public func padding(horizontal: Int = 0, vertical: Int = 0) -> PaddingView<Self> {
        PaddingView(content: self, insets: EdgeInsets(horizontal: horizontal, vertical: vertical))
    }

    /// 枠線で囲む。
    ///
    /// - Parameters:
    ///   - borderStyle: 枠線に使う文字の組み合わせ。
    ///   - style: 枠線のスタイル。
    ///   - title: 上辺に重ねる見出し。
    ///   - titleStyle: 見出しのスタイル。`nil` なら枠線と同じスタイル。
    /// - Returns: 枠線で囲んだビュー。
    public func border(
        _ borderStyle: BorderStyle = .single,
        style: Style = .plain,
        title: String? = nil,
        titleStyle: Style? = nil
    ) -> BorderView<Self> {
        BorderView(content: self, borderStyle: borderStyle, style: style, title: title, titleStyle: titleStyle)
    }

    /// 背景色を塗る。
    ///
    /// - Parameters:
    ///   - color: 背景色。
    /// - Returns: 背景を塗ったビュー。
    public func background(_ color: Color) -> BackgroundView<Self> {
        BackgroundView(content: self, style: Style(background: color))
    }

    /// 背景をスタイルごと塗る。
    ///
    /// - Parameters:
    ///   - style: 背景を塗るスタイル。
    /// - Returns: 背景を塗ったビュー。
    public func background(style: Style) -> BackgroundView<Self> {
        BackgroundView(content: self, style: style)
    }

    /// 幅・高さを固定する。
    ///
    /// - Parameters:
    ///   - width: 固定する幅。`nil` なら内容の希望に任せる。
    ///   - height: 固定する高さ。`nil` なら内容の希望に任せる。
    ///   - horizontalAlignment: 領域の中で内容を横に寄せる向き。
    ///   - verticalAlignment: 領域の中で内容を縦に寄せる向き。
    /// - Returns: サイズを固定したビュー。
    public func frame(
        width: Int? = nil,
        height: Int? = nil,
        horizontalAlignment: HorizontalAlignment = .leading,
        verticalAlignment: VerticalAlignment = .top
    ) -> FrameView<Self> {
        FrameView(
            content: self,
            width: width,
            height: height,
            horizontalAlignment: horizontalAlignment,
            verticalAlignment: verticalAlignment
        )
    }

    /// 余った領域を引き取るようにする。
    ///
    /// - Parameters:
    ///   - horizontal: 横方向の重み。
    ///   - vertical: 縦方向の重み。
    /// - Returns: 分配ルールを差し替えたビュー。
    public func flexible(horizontal: Int = 1, vertical: Int = 1) -> FlexibleView<Self> {
        FlexibleView(
            content: self,
            traits: LayoutTraits(horizontalFlex: horizontal, verticalFlex: vertical)
        )
    }

    /// 領域いっぱいを受け取り、その中で内容を寄せる。
    ///
    /// - Parameters:
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    /// - Returns: 内容を寄せて置くビュー。
    public func aligned(
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> AlignedView<Self> {
        AlignedView(content: self, horizontal: horizontal, vertical: vertical)
    }
}
