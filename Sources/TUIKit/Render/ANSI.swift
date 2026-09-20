/// よく使う ANSI エスケープシーケンス。
public enum ANSI {
    /// エスケープ文字 `ESC`。
    public static let escape = "\u{1B}"
    /// 制御シーケンス導入子 `CSI`（`ESC [`）。
    public static let csi = "\u{1B}["

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

    /// クリップボードへ渡せる Base64 の長さの上限（バイト）。
    ///
    /// - Note: 受け付ける長さは端末ごとに違い、OSC 52 の仕様にも定めがない。
    ///   この既定で足りなければ、呼び出しごとに `limit` を渡して変えられる。
    public static let clipboardLimit = 100_000

    /// カーソルを移動するシーケンスを組み立てる。
    ///
    /// - Parameters:
    ///   - row: 移動先の行。1 起点。1 未満は 1 に丸める。
    ///   - column: 移動先の列。1 起点。1 未満は 1 に丸める。
    /// - Returns: カーソルを移動するシーケンス。
    public static func moveCursor(row: Int, column: Int) -> String {
        "\u{1B}[\(max(1, row));\(max(1, column))H"
    }

    /// 文字列をクリップボードへ書き込むシーケンス（OSC 52）を組み立てる。
    ///
    /// - Parameters:
    ///   - text: クリップボードへ渡す文字列。空文字列を渡すとクリップボードを空にする。
    ///   - limit: Base64 に変換した後の長さの上限（バイト）。
    /// - Returns: クリップボードへ書き込むシーケンス。上限を超えるなら `nil`。
    /// - Note: OSC 52 を既定で拒否する端末がある（xterm の `allowWindowOps`、
    ///   tmux の `set-clipboard`）。端末は応答を返さないため、書き込めたかは送った側から
    ///   判別できない。
    public static func setClipboard(_ text: String, limit: Int = ANSI.clipboardLimit) -> String? {
        let encoded = Base64.encode(text)
        guard encoded.utf8.count <= limit else { return nil }
        return "\u{1B}]52;c;\(encoded)\u{07}"
    }
}
