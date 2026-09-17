/// 端末の基本 16 色。
public enum ANSIColor: UInt8, Hashable, Sendable, CaseIterable {
    case black = 0
    case red = 1
    case green = 2
    case yellow = 3
    case blue = 4
    case magenta = 5
    case cyan = 6
    case white = 7
    case brightBlack = 8
    case brightRed = 9
    case brightGreen = 10
    case brightYellow = 11
    case brightBlue = 12
    case brightMagenta = 13
    case brightCyan = 14
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

    public static let black = Color.ansi(.black)
    public static let red = Color.ansi(.red)
    public static let green = Color.ansi(.green)
    public static let yellow = Color.ansi(.yellow)
    public static let blue = Color.ansi(.blue)
    public static let magenta = Color.ansi(.magenta)
    public static let cyan = Color.ansi(.cyan)
    public static let white = Color.ansi(.white)
    public static let brightBlack = Color.ansi(.brightBlack)
    public static let brightRed = Color.ansi(.brightRed)
    public static let brightGreen = Color.ansi(.brightGreen)
    public static let brightYellow = Color.ansi(.brightYellow)
    public static let brightBlue = Color.ansi(.brightBlue)
    public static let brightMagenta = Color.ansi(.brightMagenta)
    public static let brightCyan = Color.ansi(.brightCyan)
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
