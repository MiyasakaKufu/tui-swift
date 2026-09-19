/// 1 セル分の見た目（文字色・背景色・装飾）。
public struct Style: Hashable, Sendable {
    /// 文字色。
    public var foreground: Color
    /// 背景色。
    public var background: Color
    /// 文字装飾。
    public var attributes: TextAttributes

    /// 文字色・背景色・装飾を指定してスタイルを作る。
    ///
    /// - Parameters:
    ///   - foreground: 文字色。
    ///   - background: 背景色。
    ///   - attributes: 文字装飾。
    public init(
        foreground: Color = .default,
        background: Color = .default,
        attributes: TextAttributes = []
    ) {
        self.foreground = foreground
        self.background = background
        self.attributes = attributes
    }

    /// 装飾なしの既定スタイル。
    public static let plain = Style()

    /// 文字色だけを差し替えたスタイル。
    ///
    /// - Parameters:
    ///   - color: 新しい文字色。
    /// - Returns: 文字色を差し替えたスタイル。
    public func withForeground(_ color: Color) -> Style {
        var copy = self
        copy.foreground = color
        return copy
    }

    /// 背景色だけを差し替えたスタイル。
    ///
    /// - Parameters:
    ///   - color: 新しい背景色。
    /// - Returns: 背景色を差し替えたスタイル。
    public func withBackground(_ color: Color) -> Style {
        var copy = self
        copy.background = color
        return copy
    }

    /// 装飾を足したスタイル。
    ///
    /// - Parameters:
    ///   - attributes: 足す装飾。
    /// - Returns: 装飾を足したスタイル。
    public func adding(_ attributes: TextAttributes) -> Style {
        var copy = self
        copy.attributes.formUnion(attributes)
        return copy
    }

    /// 装飾を外したスタイル。
    ///
    /// - Parameters:
    ///   - attributes: 外す装飾。
    /// - Returns: 装飾を外したスタイル。
    public func removing(_ attributes: TextAttributes) -> Style {
        var copy = self
        copy.attributes.subtract(attributes)
        return copy
    }

    /// 太字を足したスタイル。
    public var bold: Style { adding(.bold) }
    /// 減光を足したスタイル。
    public var dim: Style { adding(.dim) }
    /// 斜体を足したスタイル。
    public var italic: Style { adding(.italic) }
    /// 下線を足したスタイル。
    public var underline: Style { adding(.underline) }
    /// 反転を足したスタイル。
    public var reverse: Style { adding(.reverse) }
    /// 打ち消し線を足したスタイル。
    public var strikethrough: Style { adding(.strikethrough) }

    /// `previous` の状態から自分へ遷移するための SGR シーケンス。
    ///
    /// - Parameters:
    ///   - previous: 遷移前のスタイル。
    /// - Returns: 遷移に必要な SGR シーケンス。差分がなければ空文字列。
    /// - Note: 装飾を落とす必要がある場合は、いったん全解除（SGR 0）してから再設定する。
    public func sgrSequence(transitioningFrom previous: Style) -> String {
        if self == previous { return "" }

        var parameters: [String] = []
        let removed = previous.attributes.subtracting(attributes)

        if removed.isEmpty {
            parameters.append(contentsOf: attributes.subtracting(previous.attributes).enableParameters)
            if foreground != previous.foreground {
                parameters.append(contentsOf: foreground.foregroundParameters)
            }
            if background != previous.background {
                parameters.append(contentsOf: background.backgroundParameters)
            }
        } else {
            parameters.append("0")
            parameters.append(contentsOf: attributes.enableParameters)
            if foreground != .default {
                parameters.append(contentsOf: foreground.foregroundParameters)
            }
            if background != .default {
                parameters.append(contentsOf: background.backgroundParameters)
            }
        }

        if parameters.isEmpty { return "" }
        return ANSI.csi + parameters.joined(separator: ";") + "m"
    }
}
