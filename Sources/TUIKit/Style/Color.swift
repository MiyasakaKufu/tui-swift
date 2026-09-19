/// 端末の基本 16 色。
public enum ANSIColor: UInt8, Hashable, Sendable, CaseIterable {
    /// 黒。
    case black = 0
    /// 赤。
    case red = 1
    /// 緑。
    case green = 2
    /// 黄。
    case yellow = 3
    /// 青。
    case blue = 4
    /// マゼンタ。
    case magenta = 5
    /// シアン。
    case cyan = 6
    /// 白。
    case white = 7
    /// 明るい黒（灰色）。
    case brightBlack = 8
    /// 明るい赤。
    case brightRed = 9
    /// 明るい緑。
    case brightGreen = 10
    /// 明るい黄。
    case brightYellow = 11
    /// 明るい青。
    case brightBlue = 12
    /// 明るいマゼンタ。
    case brightMagenta = 13
    /// 明るいシアン。
    case brightCyan = 14
    /// 明るい白。
    case brightWhite = 15
}

/// 文字色・背景色。
public enum Color: Hashable, Sendable {
    /// 端末の既定色（SGR 39 / 49）。
    case `default`
    /// 基本 16 色。
    case ansi(ANSIColor)
    /// xterm 256 色。
    case xterm256(UInt8)
    /// 24 ビットカラー（トゥルーカラー）。対応していない端末では無視される。
    case rgb(r: UInt8, g: UInt8, b: UInt8)

    /// 基本 16 色の黒。
    public static let black = Color.ansi(.black)
    /// 基本 16 色の赤。
    public static let red = Color.ansi(.red)
    /// 基本 16 色の緑。
    public static let green = Color.ansi(.green)
    /// 基本 16 色の黄。
    public static let yellow = Color.ansi(.yellow)
    /// 基本 16 色の青。
    public static let blue = Color.ansi(.blue)
    /// 基本 16 色のマゼンタ。
    public static let magenta = Color.ansi(.magenta)
    /// 基本 16 色のシアン。
    public static let cyan = Color.ansi(.cyan)
    /// 基本 16 色の白。
    public static let white = Color.ansi(.white)
    /// 基本 16 色の明るい黒（灰色）。
    public static let brightBlack = Color.ansi(.brightBlack)
    /// 基本 16 色の明るい赤。
    public static let brightRed = Color.ansi(.brightRed)
    /// 基本 16 色の明るい緑。
    public static let brightGreen = Color.ansi(.brightGreen)
    /// 基本 16 色の明るい黄。
    public static let brightYellow = Color.ansi(.brightYellow)
    /// 基本 16 色の明るい青。
    public static let brightBlue = Color.ansi(.brightBlue)
    /// 基本 16 色の明るいマゼンタ。
    public static let brightMagenta = Color.ansi(.brightMagenta)
    /// 基本 16 色の明るいシアン。
    public static let brightCyan = Color.ansi(.brightCyan)
    /// 基本 16 色の明るい白。
    public static let brightWhite = Color.ansi(.brightWhite)

    /// 文字色として指定するときの SGR パラメータ列。
    public var foregroundParameters: [String] {
        switch self {
        case .default:
            return ["39"]
        case .ansi(let color):
            let value = Int(color.rawValue)
            return [value < 8 ? String(30 + value) : String(90 + value - 8)]
        case .xterm256(let index):
            return ["38", "5", String(index)]
        case .rgb(let r, let g, let b):
            return ["38", "2", String(r), String(g), String(b)]
        }
    }

    /// 背景色として指定するときの SGR パラメータ列。
    public var backgroundParameters: [String] {
        switch self {
        case .default:
            return ["49"]
        case .ansi(let color):
            let value = Int(color.rawValue)
            return [value < 8 ? String(40 + value) : String(100 + value - 8)]
        case .xterm256(let index):
            return ["48", "5", String(index)]
        case .rgb(let r, let g, let b):
            return ["48", "2", String(r), String(g), String(b)]
        }
    }
}
