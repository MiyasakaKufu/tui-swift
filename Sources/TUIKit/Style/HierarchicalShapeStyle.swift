/// ``HierarchicalShapeStyle`` を渡した ``View`` を内側に含む ``View`` の `View.foregroundStyle(_: Color)`・`View.foregroundStyle(_:_:)` が決めた前景スタイルの、プライマリレベルかセカンダリレベル。
///
/// 自分の色を持たない。
///
/// ```swift
/// VStack {
///     Text("名前")
///     Text("補足").foregroundStyle(.secondary)
/// }
/// .foregroundStyle(.white, .brightBlack)
/// ```
///
/// - Note: セカンダリレベルを `View.foregroundStyle(_:_:)` で決めていなければ、プライマリレベルの文字色に ``TextAttributes/dim`` を足したものになる。
public struct HierarchicalShapeStyle: Hashable, Sendable {
    /// レベル。
    enum Level: Hashable, Sendable {
        /// プライマリレベル。
        case primary
        /// セカンダリレベル。
        case secondary
    }

    /// この ``HierarchicalShapeStyle`` が指すレベル。
    let level: Level

    /// 前景スタイルのプライマリレベル。どの ``View`` でも決めていなければ ``Color/default``。
    public static let primary = HierarchicalShapeStyle(level: .primary)
    /// 前景スタイルのセカンダリレベル。
    public static let secondary = HierarchicalShapeStyle(level: .secondary)
}

/// `View.foregroundStyle(_: Color)`・`Text.foregroundStyle(_: Color)` などに渡した文字色。
enum ForegroundStyleValue: Hashable, Sendable {
    /// 色そのもの。
    case color(Color)
    /// 前景スタイルのレベル。
    case hierarchical(HierarchicalShapeStyle)
}

/// ``RenderContext`` が、`RenderContext` のメソッドに `child` 引数として渡す ``View`` へ運ぶ前景スタイル・ティントカラー・背景色。
///
/// `View.foregroundStyle(_: Color)`・``View/tint(_:)``・``View/background(_:)`` が書き換え、``Text``・``ListView`` などが ``Style`` を決めるときに使う。
struct ViewColors: Hashable, Sendable {
    /// プライマリレベルの ``Style``。``Style/background`` は使わない。
    var primary = Style()
    /// セカンダリレベルの ``Style``。`nil` なら `primary` に ``TextAttributes/dim`` を足したもの。``Style/background`` は使わない。
    var secondary: Style?
    /// ``View/tint(_:)`` で決めたティントカラー。`nil` ならプライマリレベルの文字色。
    var tint: Color?
    /// ``View/background(_:)`` で塗った背景色。
    var background = Color.default

    /// `value` の文字色に、背景色を合わせた ``Style`` を返す。
    ///
    /// - Parameters:
    ///   - value: 文字色。
    /// - Returns: `value` の文字色と装飾に、``ViewColors/background`` を背景色にした ``Style``。
    func style(_ value: ForegroundStyleValue) -> Style {
        var style = foreground(value)
        style.background = background
        return style
    }

    /// ティントカラーを文字色にし、背景色を合わせた ``Style`` を返す。
    ///
    /// - Returns: ``ViewColors/tint`` が `nil` ならプライマリレベルの ``Style``、そうでなければ ``ViewColors/tint`` を文字色にした ``Style``。背景色は ``ViewColors/background``。
    func tintStyle() -> Style {
        guard let tint else { return style(.hierarchical(.primary)) }
        return Style(foreground: tint, background: background)
    }

    /// `value` の文字色を、背景色を除いて返す。
    ///
    /// - Parameters:
    ///   - value: 文字色。
    /// - Returns: `value` の文字色と装飾の ``Style``。背景色は ``Color/default``。
    private func foreground(_ value: ForegroundStyleValue) -> Style {
        switch value {
        case .color(let color):
            return Style(foreground: color)
        case .hierarchical(let hierarchical):
            switch hierarchical.level {
            case .primary:
                return primary
            case .secondary:
                return secondary ?? primary.adding(.dim)
            }
        }
    }

    /// 前景スタイルを `primary` と `secondary` に決め直す。
    ///
    /// - Parameters:
    ///   - primary: プライマリレベルにする文字色。
    ///   - secondary: セカンダリレベルにする文字色。`nil` なら、`primary` に ``TextAttributes/dim`` を足したものになる。
    /// - Postcondition: `primary` が ``HierarchicalShapeStyle`` なら、決め直す前のレベルの ``Style`` がプライマリレベルになる。
    mutating func setForeground(_ primary: ForegroundStyleValue, secondary: Color?) {
        self.primary = foreground(primary)
        self.secondary = secondary.map { Style(foreground: $0) }
    }
}
