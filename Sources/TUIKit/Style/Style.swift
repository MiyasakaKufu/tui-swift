/// 1 セル分の見た目（文字色・背景色・装飾）。
public struct Style: Hashable, Sendable {
    public var foreground: Color
    public var background: Color
    public var attributes: TextAttributes

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

    public func withForeground(_ color: Color) -> Style {
        var copy = self
        copy.foreground = color
        return copy
    }

    public func withBackground(_ color: Color) -> Style {
        var copy = self
        copy.background = color
        return copy
    }

    public func adding(_ attributes: TextAttributes) -> Style {
        var copy = self
        copy.attributes.formUnion(attributes)
        return copy
    }

    public func removing(_ attributes: TextAttributes) -> Style {
        var copy = self
        copy.attributes.subtract(attributes)
        return copy
    }

    public var bold: Style { adding(.bold) }
    public var dim: Style { adding(.dim) }
    public var italic: Style { adding(.italic) }
    public var underline: Style { adding(.underline) }
    public var reverse: Style { adding(.reverse) }
    public var strikethrough: Style { adding(.strikethrough) }

    /// `previous` の状態から自分へ遷移するための SGR シーケンス。
    ///
    /// 差分がなければ空文字列を返す。装飾を落とす必要がある場合だけ
    /// いったん全解除（SGR 0）してから再設定する。
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
