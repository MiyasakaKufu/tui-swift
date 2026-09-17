/// よく使う ANSI エスケープシーケンス。
public enum ANSI {
    public static let escape = "\u{1B}"
    public static let csi = "\u{1B}["

    public static let reset = "\u{1B}[0m"
    public static let clearScreen = "\u{1B}[2J"
    public static let clearLine = "\u{1B}[2K"
    public static let cursorHome = "\u{1B}[H"

    public static let hideCursor = "\u{1B}[?25l"
    public static let showCursor = "\u{1B}[?25h"

    public static let enterAlternateScreen = "\u{1B}[?1049h"
    public static let exitAlternateScreen = "\u{1B}[?1049l"

    /// クリック・ドラッグ・ホイールを SGR 拡張形式（1006）で受け取る。
    public static let enableMouseTracking = "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
    public static let disableMouseTracking = "\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l"

    public static let enableBracketedPaste = "\u{1B}[?2004h"
    public static let disableBracketedPaste = "\u{1B}[?2004l"

    public static let enableFocusReporting = "\u{1B}[?1004h"
    public static let disableFocusReporting = "\u{1B}[?1004l"

    /// カーソルを移動する。行・列はいずれも 1 起点。
    public static func moveCursor(row: Int, column: Int) -> String {
        "\u{1B}[\(max(1, row));\(max(1, column))H"
    }
}
