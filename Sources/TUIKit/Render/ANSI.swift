/// よく使う ANSI エスケープシーケンス。
public enum ANSI {
    /// エスケープ文字 `ESC`。
    public static let escape = "\u{1B}"
    /// 制御シーケンス導入子 `CSI`（`ESC [`）。
    public static let csi = "\u{1B}["
    /// オペレーティングシステムコマンド導入子 `OSC`（`ESC ]`）。
    public static let osc = "\u{1B}]"
    /// `OSC` の文字列を終える `BEL`。
    public static let bell = "\u{07}"

    /// 文字色・背景色・装飾をすべて解除する。
    public static let reset = "\u{1B}[0m"
    /// 画面全体を消す。
    public static let clearScreen = "\u{1B}[2J"
    /// カーソルがある行を消す。
    public static let clearLine = "\u{1B}[2K"
    /// カーソルを左上へ移動する。
    public static let cursorHome = "\u{1B}[H"

    /// カーソルを隠す。
    public static let hideCursor = "\u{1B}[?25l"
    /// カーソルを表示する。
    public static let showCursor = "\u{1B}[?25h"

    /// 代替画面バッファへ切り替える。
    public static let enterAlternateScreen = "\u{1B}[?1049h"
    /// 代替画面バッファから元の画面へ戻る。
    public static let exitAlternateScreen = "\u{1B}[?1049l"

    /// クリック・ドラッグ・ホイールを SGR 拡張形式（1006）で受け取る。
    public static let enableMouseTracking = "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
    /// マウスの通知を止める。
    public static let disableMouseTracking = "\u{1B}[?1006l\u{1B}[?1002l\u{1B}[?1000l"

    /// 貼り付けを `ESC [ 200 ~` と `ESC [ 201 ~` で囲んで受け取る。
    public static let enableBracketedPaste = "\u{1B}[?2004h"
    /// ブラケットペーストの通知を止める。
    public static let disableBracketedPaste = "\u{1B}[?2004l"

    /// 同期出力（DECSET 2026）を開始し、終了するまで画面の更新を保留させる。
    ///
    /// - Note: 対応しない端末はこの制御コードを読み飛ばすため、送っても表示は変わらない。
    public static let beginSynchronizedUpdate = "\u{1B}[?2026h"
    /// 同期出力を終了し、保留していた更新をまとめて表示させる。
    public static let endSynchronizedUpdate = "\u{1B}[?2026l"

    /// 今のウィンドウタイトルとアイコン名を端末のスタックへ積む。
    ///
    /// - Note: タイトルのスタックに対応しない端末はこの制御コードを読み飛ばすため、
    ///   積まれない。
    public static let saveWindowTitle = "\u{1B}[22;0t"
    /// 端末のスタックからウィンドウタイトルとアイコン名を戻す。
    ///
    /// - Note: スタックが空なら何も起きない。
    public static let restoreWindowTitle = "\u{1B}[23;0t"

    /// 端末のフォーカス変化を受け取る。
    public static let enableFocusReporting = "\u{1B}[?1004h"
    /// フォーカス変化の通知を止める。
    public static let disableFocusReporting = "\u{1B}[?1004l"

    /// kitty keyboard protocol の対応状況を問い合わせる。
    ///
    /// - Note: 対応する端末だけが `CSI ? <flags> u` を返す。対応しない端末は何も返さない。
    public static let queryKeyboardProtocol = "\u{1B}[?u"
    /// 端末の種別を問い合わせる。
    ///
    /// - Note: どの端末も `CSI ? <params> c` を返すため、先に送った問い合わせの応答が
    ///   出揃ったことを知る目印に使える。
    public static let queryDeviceAttributes = "\u{1B}[c"

    /// キーの曖昧さを解消する形式（kitty keyboard protocol の flag 1）でキーを受け取る。
    public static let enableKeyboardProtocol = "\u{1B}[=1u"
    /// kitty keyboard protocol のすべてのフラグを落とし、従来の形式へ戻す。
    public static let disableKeyboardProtocol = "\u{1B}[=0u"

    /// ウィンドウタイトルとアイコン名を設定するシーケンスを組み立てる。
    ///
    /// - Parameters:
    ///   - title: 設定するタイトル。
    /// - Returns: タイトルを設定するシーケンス。
    /// - Note: `title` の制御文字は取り除く。
    public static func setWindowTitle(_ title: String) -> String {
        let scalars = title.unicodeScalars.filter { $0.properties.generalCategory != .control }
        return osc + "0;" + String(String.UnicodeScalarView(scalars)) + bell
    }

    /// カーソル形状を設定するシーケンスを組み立てる。
    ///
    /// - Parameters:
    ///   - shape: 設定する形。
    /// - Returns: カーソル形状を設定するシーケンス。
    public static func setCursorShape(_ shape: CursorShape) -> String {
        "\u{1B}[\(shape.parameter) q"
    }

    /// カーソルを移動するシーケンスを組み立てる。
    ///
    /// - Parameters:
    ///   - row: 移動先の行。1 起点。1 未満は 1 に丸める。
    ///   - column: 移動先の列。1 起点。1 未満は 1 に丸める。
    /// - Returns: カーソルを移動するシーケンス。
    public static func moveCursor(row: Int, column: Int) -> String {
        "\u{1B}[\(max(1, row));\(max(1, column))H"
    }
}
