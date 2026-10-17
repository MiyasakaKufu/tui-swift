/// 外側の `View.foregroundStyle(_: Color)`・`View.foregroundStyle(_:_:)` が決めた文字色の、primary か secondary の段。
///
/// 自分の色を持たず、外側で決めた文字色から決まる。
///
/// ```swift
/// VStack {
///     Text("名前")
///     Text("補足").foregroundStyle(.secondary)
/// }
/// .foregroundStyle(.white, .brightBlack)
/// ```
///
/// - Note: secondary の段を `View.foregroundStyle(_:_:)` で決めていなければ、primary の段の文字色に ``TextAttributes/dim`` を足したものになる。
public struct HierarchicalShapeStyle: Hashable, Sendable {
    /// 段。
    enum Level: Hashable, Sendable {
        /// 1 段目。
        case primary
        /// 2 段目。
        case secondary
    }

    /// この ``HierarchicalShapeStyle`` が指す段。
    let level: Level

    /// 外側で決めた文字色そのもの。どこでも決めていなければ ``Color/default``。
    public static let primary = HierarchicalShapeStyle(level: .primary)
    /// 外側で決めた文字色の 2 段目。
    public static let secondary = HierarchicalShapeStyle(level: .secondary)
}

/// `View.foregroundStyle(_: Color)`・`Text.foregroundStyle(_: Color)` などに渡した文字色。
enum ForegroundStyleValue: Hashable, Sendable {
    /// 色そのもの。
    case color(Color)
    /// 外側で決めた文字色の段。
    case hierarchical(HierarchicalShapeStyle)
}

/// ``RenderContext`` が、`RenderContext` のメソッドに `child` 引数として渡す ``View`` へ運ぶ文字色・tint・背景色。
///
/// `View.foregroundStyle(_: Color)`・``View/tint(_:)``・``View/background(_:)`` が書き換え、``Text``・``ListView`` などが ``Style`` を決めるときに使う。
struct ViewColors: Hashable, Sendable {
    /// primary の段の ``Style``。``Style/background`` は使わない。
    var primary = Style()
    /// secondary の段の ``Style``。`nil` なら `primary` に ``TextAttributes/dim`` を足したもの。``Style/background`` は使わない。
    var secondary: Style?
    /// ``View/tint(_:)`` で決めた色。`nil` なら primary の段の文字色。
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

    /// tint の文字色に、背景色を合わせた ``Style`` を返す。
    ///
    /// - Returns: ``ViewColors/tint`` が `nil` なら primary の段の ``Style``、そうでなければ ``ViewColors/tint`` を文字色にした ``Style``。背景色は ``ViewColors/background``。
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

    /// 文字色を `primary` と `secondary` に決め直す。
    ///
    /// - Parameters:
    ///   - primary: primary の段にする文字色。
    ///   - secondary: secondary の段にする文字色。`nil` なら、`primary` に ``TextAttributes/dim`` を足したものになる。
    /// - Postcondition: `primary` が ``HierarchicalShapeStyle`` なら、決め直す前の段の ``Style`` が primary の段になる。
    mutating func setForeground(_ primary: ForegroundStyleValue, secondary: Color?) {
        self.primary = foreground(primary)
        self.secondary = secondary.map { Style(foreground: $0) }
    }
}
