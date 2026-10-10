/// `PaddingView.content` の上下左右に `insets` の長さを空ける `View`。
public struct PaddingView<Content: View>: PrimitiveView {
    /// `insets` の内側に置く `View`。
    public var content: Content
    /// `PaddingView.content` の上下左右に空ける長さ（左右は `Cell` の数、上下は行の数で表す）。
    public var insets: EdgeInsets

    /// `content` と `insets` を指定して `PaddingView` を作る。
    ///
    /// - Parameters:
    ///   - content: `insets` の内側に置く `View`。
    ///   - insets: `content` の上下左右に空ける長さ（左右は `Cell` の数、上下は行の数で表す）。
    public init(content: Content, insets: EdgeInsets) {
        self.content = content
        self.insets = insets
    }

    /// `PaddingView.content` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `PaddingView.content` の `View.layoutTraits(context:)` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// `PaddingView.content` の `View.sizeThatFits(_:context:)` の戻り値に `insets` を足した `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `PaddingView.content` の `View.sizeThatFits(_:context:)` の戻り値に `insets` を足した `Size`。`proposal` は超えない。
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

    /// `insets` の内側へ `PaddingView.content` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: `insets` を含めた矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        let inner = rect.inset(by: insets)
        guard !inner.isEmpty else { return }
        context.render(content, index: 0, into: &buffer, rect: inner)
    }
}

/// `BorderView.content` を枠線で囲む `View`。
public struct BorderView<Content: View>: PrimitiveView {
    /// 枠線の内側に置く `View`。
    public var content: Content
    /// 枠線に使う文字の組み合わせ。
    public var borderStyle: BorderStyle
    /// 枠線のスタイル。
    public var style: Style
    /// 上辺に重ねる見出し。`nil` なら見出しを出さない。
    public var title: String?
    /// 見出しのスタイル。`nil` なら枠線と同じスタイル。
    public var titleStyle: Style?

    /// `content` と枠線の見た目を指定して `BorderView` を作る。
    ///
    /// - Parameters:
    ///   - content: 枠線の内側に置く `View`。
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

    /// `BorderView.content` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `BorderView.content` の `View.layoutTraits(context:)` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// `BorderView.content` の `View.sizeThatFits(_:context:)` の戻り値に、枠線の `Cell` 2 個分・2 行を足した `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `BorderView.content` の `View.sizeThatFits(_:context:)` の戻り値に枠線を足した `Size`。見出しがあれば、それが収まる幅まで広げる。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let inner = Size(width: proposal.width - 2, height: proposal.height - 2)
        let desired = context.sizeThatFits(of: content, index: 0, proposal: inner)
        var width = desired.width + 2
        if let titleText = title {
            let ambiguous = context.ambiguousWidth
            let expanded = TabExpansion.expand(titleText, ambiguous: ambiguous)
            width = max(width, DisplayWidth.width(of: expanded, ambiguous: ambiguous) + 4)
        }
        return Size(
            width: min(width, proposal.width),
            height: min(desired.height + 2, proposal.height)
        )
    }

    /// 枠線と見出しを描き、内側へ `BorderView.content` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 枠線を含めた矩形。幅・高さが 2 未満なら何も描かない。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard rect.width >= 2, rect.height >= 2 else { return }
        drawFrame(into: &buffer, rect: rect, ambiguous: context.ambiguousWidth)
        let inner = rect.inset(by: 1)
        if !inner.isEmpty {
            context.render(content, index: 0, into: &buffer, rect: inner)
        }
    }

    /// 実際に枠として描く文字の組み合わせを返す。
    ///
    /// - Parameters:
    ///   - ambiguous: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    /// - Returns: `borderStyle` の文字がどれも `Cell` 1 個分に収まれば `borderStyle`、収まらなければ `.ascii`。
    func effectiveBorderStyle(ambiguous: DisplayWidth.AmbiguousWidth) -> BorderStyle {
        borderStyle.fitsInSingleColumn(ambiguous: ambiguous) ? borderStyle : .ascii
    }

    /// 枠線と見出しを描く。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 枠線を含めた矩形。
    ///   - ambiguous: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    private func drawFrame(into buffer: inout Buffer, rect: Rect, ambiguous: DisplayWidth.AmbiguousWidth) {
        let border = effectiveBorderStyle(ambiguous: ambiguous)
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
            // 幅で切り詰める前に展開しないと、タブの分だけ `Cell` の数の計算がずれる。
            let expanded = TabExpansion.expand(" " + titleText + " ", ambiguous: ambiguous)
            let trimmed = DisplayWidth.truncate(expanded, to: available + 2, ambiguous: ambiguous)
            buffer.write(
                trimmed,
                at: Point(x: left + 1, y: top),
                style: titleStyle ?? style,
                clippedTo: Rect(x: left + 1, y: top, width: rect.width - 2, height: 1)
            )
        }
    }
}

/// `BackgroundView.content` の背景を塗る `View`。
public struct BackgroundView<Content: View>: PrimitiveView {
    /// 背景の上に置く `View`。
    public var content: Content
    /// 背景を塗るスタイル。
    public var style: Style

    /// `content` と背景のスタイルを指定して `BackgroundView` を作る。
    ///
    /// - Parameters:
    ///   - content: 背景の上に置く `View`。
    ///   - style: 背景を塗るスタイル。
    public init(content: Content, style: Style) {
        self.content = content
        self.style = style
    }

    /// `BackgroundView.content` の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `BackgroundView.content` の `View.layoutTraits(context:)` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// `BackgroundView.content` の `View.sizeThatFits(_:context:)` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `BackgroundView.content` の `View.sizeThatFits(_:context:)` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// `rect` を塗ってから `BackgroundView.content` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard !rect.isEmpty else { return }
        buffer.fill(rect, style: style)
        context.render(content, index: 0, into: &buffer, rect: rect)
    }
}

/// サイズを固定する `View`。負の幅・高さは 0 に丸められる。
public struct FrameView<Content: View>: PrimitiveView {
    /// 固定した領域に置く `View`。
    public var content: Content
    /// 固定する幅。`nil` なら `FrameView.content` の `View.sizeThatFits(_:context:)` の戻り値に任せる。負の値は 0 に丸められる。
    public var width: Int? {
        didSet { width = width.map { max(0, $0) } }
    }
    /// 固定する高さ。`nil` なら `FrameView.content` の `View.sizeThatFits(_:context:)` の戻り値に任せる。負の値は 0 に丸められる。
    public var height: Int? {
        didSet { height = height.map { max(0, $0) } }
    }
    /// 領域の中で `FrameView.content` を横に寄せる向き。
    public var horizontalAlignment: HorizontalAlignment
    /// 領域の中で `FrameView.content` を縦に寄せる向き。
    public var verticalAlignment: VerticalAlignment

    /// `content` と固定するサイズを指定して `FrameView` を作る。
    ///
    /// - Parameters:
    ///   - content: 固定した領域に置く `View`。
    ///   - width: 固定する幅。`nil` なら `content` の `View.sizeThatFits(_:context:)` の戻り値に任せる。
    ///   - height: 固定する高さ。`nil` なら `content` の `View.sizeThatFits(_:context:)` の戻り値に任せる。
    ///   - horizontalAlignment: 領域の中で `content` を横に寄せる向き。
    ///   - verticalAlignment: 領域の中で `content` を縦に寄せる向き。
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

    /// `width` を固定していれば `LayoutTraits.horizontalFlex`、`height` を固定していれば `LayoutTraits.verticalFlex` を 0 にし、ほかは
    /// `FrameView.content` の `View.layoutTraits(context:)` の戻り値のままにした `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `FrameView.content` の `View.layoutTraits(context:)` の戻り値の、`width` を固定していれば
    ///   `LayoutTraits.horizontalFlex`、`height` を固定していれば `LayoutTraits.verticalFlex` を 0 にした `LayoutTraits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        let traits = context.layoutTraits(of: content, index: 0)
        return LayoutTraits(
            horizontalFlex: width == nil ? traits.horizontalFlex : 0,
            verticalFlex: height == nil ? traits.verticalFlex : 0
        )
    }

    /// 固定したサイズ、または `FrameView.content` の `View.sizeThatFits(_:context:)` の戻り値を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 固定した方向は `width`・`height`、固定していない方向は `FrameView.content` の `View.sizeThatFits(_:context:)` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        let desired = context.sizeThatFits(of: content, index: 0, proposal: proposal)
        return Size(
            width: min(width ?? desired.width, proposal.width),
            height: min(height ?? desired.height, proposal.height)
        )
    }

    /// 固定したサイズの領域へ `FrameView.content` を寄せて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
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

/// `LayoutTraits` だけを差し替える `View`。
public struct FlexibleView<Content: View>: PrimitiveView {
    /// `LayoutTraits` を差し替える `View`。
    public var content: Content
    /// `FlexibleView.content` の `View.layoutTraits(context:)` の戻り値の代わりに使う `LayoutTraits`。
    public var traits: LayoutTraits

    /// `content` と `traits` を指定して `FlexibleView` を作る。
    ///
    /// - Parameters:
    ///   - content: `LayoutTraits` を差し替える `View`。
    ///   - traits: `content` の `View.layoutTraits(context:)` の戻り値の代わりに使う `LayoutTraits`。
    public init(content: Content, traits: LayoutTraits) {
        self.content = content
        self.traits = traits
    }

    /// `traits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `traits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { traits }

    /// `FlexibleView.content` の `View.sizeThatFits(_:context:)` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `FlexibleView.content` の `View.sizeThatFits(_:context:)` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// `rect` へ `FlexibleView.content` をそのまま描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(content, index: 0, into: &buffer, rect: rect)
    }
}

/// 与えられた領域の中で `AlignedView.content` を寄せる `View`。
public struct AlignedView<Content: View>: PrimitiveView {
    /// 領域の中に寄せて置く `View`。
    public var content: Content
    /// 横に寄せる向き。
    public var horizontal: HorizontalAlignment
    /// 縦に寄せる向き。
    public var vertical: VerticalAlignment

    /// `content` と寄せる向きを指定して `AlignedView` を作る。
    ///
    /// - Parameters:
    ///   - content: 領域の中に寄せて置く `View`。
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    public init(content: Content, horizontal: HorizontalAlignment, vertical: VerticalAlignment) {
        self.content = content
        self.horizontal = horizontal
        self.vertical = vertical
    }

    /// `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` がともに 1 の `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: 常に `.flexible`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits { .flexible }

    /// `proposal` をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `proposal` と同じサイズ。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size { proposal }

    /// `rect` の中で `AlignedView.content` を寄せて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
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
    /// 上下左右に `insets` の長さを空ける。
    ///
    /// - Parameters:
    ///   - insets: 上下左右に空ける長さ（左右は `Cell` の数、上下は行の数で表す）。
    /// - Returns: この `View` を `PaddingView.content` にした `PaddingView`。
    public func padding(_ insets: EdgeInsets) -> PaddingView<Self> {
        PaddingView(content: self, insets: insets)
    }

    /// 上下左右に同じ長さを空ける。
    ///
    /// - Parameters:
    ///   - amount: 上下左右のそれぞれに空ける長さ（左右は `Cell` の数、上下は行の数で表す）。
    /// - Returns: この `View` を `PaddingView.content` にした `PaddingView`。
    public func padding(_ amount: Int) -> PaddingView<Self> {
        PaddingView(content: self, insets: EdgeInsets(all: amount))
    }

    /// 左右に `horizontal`、上下に `vertical` の長さを空ける。
    ///
    /// - Parameters:
    ///   - horizontal: 左右に空ける長さ（`Cell` の数で表す）。
    ///   - vertical: 上下に空ける行の数。
    /// - Returns: この `View` を `PaddingView.content` にした `PaddingView`。
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
    /// - Returns: この `View` を `BorderView.content` にした `BorderView`。
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
    /// - Returns: この `View` を `BackgroundView.content` にした `BackgroundView`。
    public func background(_ color: Color) -> BackgroundView<Self> {
        BackgroundView(content: self, style: Style(background: color))
    }

    /// 背景をスタイルごと塗る。
    ///
    /// - Parameters:
    ///   - style: 背景を塗るスタイル。
    /// - Returns: この `View` を `BackgroundView.content` にした `BackgroundView`。
    public func background(style: Style) -> BackgroundView<Self> {
        BackgroundView(content: self, style: style)
    }

    /// 幅・高さを固定する。
    ///
    /// - Parameters:
    ///   - width: 固定する幅。`nil` なら、この `View` の `View.sizeThatFits(_:context:)` の戻り値に任せる。
    ///   - height: 固定する高さ。`nil` なら、この `View` の `View.sizeThatFits(_:context:)` の戻り値に任せる。
    ///   - horizontalAlignment: 領域の中でこの `View` を横に寄せる向き。
    ///   - verticalAlignment: 領域の中でこの `View` を縦に寄せる向き。
    /// - Returns: この `View` を `FrameView.content` にした `FrameView`。
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

    /// `VStack`・`HStack` が配ったあとに残る `Size` を引き取るようにする。
    ///
    /// - Parameters:
    ///   - horizontal: `LayoutTraits.horizontalFlex` にする整数。
    ///   - vertical: `LayoutTraits.verticalFlex` にする整数。
    /// - Returns: この `View` を `FlexibleView.content` にした `FlexibleView`。
    public func flexible(horizontal: Int = 1, vertical: Int = 1) -> FlexibleView<Self> {
        FlexibleView(
            content: self,
            traits: LayoutTraits(horizontalFlex: horizontal, verticalFlex: vertical)
        )
    }

    /// 与えられた領域いっぱいを受け取り、その中でこの `View` を寄せる。
    ///
    /// - Parameters:
    ///   - horizontal: 横に寄せる向き。
    ///   - vertical: 縦に寄せる向き。
    /// - Returns: この `View` を `AlignedView.content` にした `AlignedView`。
    public func aligned(
        horizontal: HorizontalAlignment = .center,
        vertical: VerticalAlignment = .center
    ) -> AlignedView<Self> {
        AlignedView(content: self, horizontal: horizontal, vertical: vertical)
    }
}
