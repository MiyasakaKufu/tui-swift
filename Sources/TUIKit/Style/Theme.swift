/// 役割ごとの ``Style`` をまとめた配色。
///
/// ``ApplicationOptions/theme`` に渡すと、``View`` は ``RenderContext/theme`` で読める。``Text``・``ListView``・``TextField``・``ProgressBar``・``Fill``・``Divider`` と ``View/border(_:style:title:titleStyle:)`` は、``Style`` の引数を省くと、この型のプロパティの ``Style`` で描く。``Style`` の引数を渡せば、その ``Style`` で描く。
///
/// ```swift
/// static var options: ApplicationOptions {
///     ApplicationOptions(theme: Theme(accent: Style(foreground: .magenta).bold))
/// }
/// ```
///
/// - Note: 端末エミュレータの背景色の明暗に合わせて切り替わらない。背景色が明るくても暗くても読める配色が要るなら、``Theme/monochrome`` を渡す。
public struct Theme: Hashable, Sendable {
    /// 通常の文字の ``Style``。
    public var text: Style
    /// 補足や ``TextField`` のプレースホルダのように、通常の文字より目立たせない文字の ``Style``。
    public var secondaryText: Style
    /// 目立たせる文字と、``ProgressBar`` の進んだ部分の ``Style``。
    public var accent: Style
    /// ``ListView`` の選択行のように、選択している項目の ``Style``。
    public var selection: Style
    /// 枠線と ``Divider`` の ``Style``。
    public var border: Style
    /// エラーを示す文字の ``Style``。
    public var error: Style
    /// 警告を示す文字の ``Style``。
    public var warning: Style

    /// 役割ごとの ``Style`` を指定して ``Theme`` を作る。省いた引数には ``Theme/standard`` と同じ ``Style`` が入る。
    ///
    /// - Parameters:
    ///   - text: 通常の文字の ``Style``。
    ///   - secondaryText: 通常の文字より目立たせない文字の ``Style``。
    ///   - accent: 目立たせる文字と、``ProgressBar`` の進んだ部分の ``Style``。
    ///   - selection: 選択している項目の ``Style``。
    ///   - border: 枠線と ``Divider`` の ``Style``。
    ///   - error: エラーを示す文字の ``Style``。
    ///   - warning: 警告を示す文字の ``Style``。
    public init(
        text: Style = .plain,
        secondaryText: Style = Style(foreground: .brightBlack),
        accent: Style = Style(foreground: .green),
        selection: Style = Style(attributes: .reverse),
        border: Style = .plain,
        error: Style = Style(foreground: .red),
        warning: Style = Style(foreground: .yellow)
    ) {
        self.text = text
        self.secondaryText = secondaryText
        self.accent = accent
        self.selection = selection
        self.border = border
        self.error = error
        self.warning = warning
    }

    /// ``ApplicationOptions/theme`` を省いたときの ``Theme``。
    public static let standard = Theme()

    /// 文字色にも背景色にも ``Color/default`` だけを使い、役割を装飾で分ける ``Theme``。
    public static let monochrome = Theme(
        text: .plain,
        secondaryText: Style.plain.dim,
        accent: Style.plain.bold,
        selection: Style.plain.reverse,
        border: .plain,
        error: Style.plain.bold.underline,
        warning: Style.plain.underline
    )
}
