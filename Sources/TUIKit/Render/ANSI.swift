/// 端末デバイスへ書き出す `String` の定数と、それを組み立てる関数をまとめた型。
public enum ANSI {
    /// エスケープ文字 `ESC`。
    public static let escape = "\u{1B}"
    /// CSI（Control Sequence Introducer）の `ESC [`。
    ///
    /// - See: [ECMA-48: Control Functions for Coded Character Sets](https://ecma-international.org/publications-and-standards/standards/ecma-48/)
    ///   の「CSI - CONTROL SEQUENCE INTRODUCER」。
    public static let csi = "\u{1B}["
    /// OSC（Operating System Command）の `ESC ]`。
    ///
    /// - See: [ECMA-48: Control Functions for Coded Character Sets](https://ecma-international.org/publications-and-standards/standards/ecma-48/)
    ///   の「OSC - OPERATING SYSTEM COMMAND」。
    public static let osc = "\u{1B}]"
    /// `ANSI.osc` で始めた `String` を終える `BEL`。
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

    /// 端末エミュレータの代替画面（alternate screen）へ切り替える。
    public static let enterAlternateScreen = "\u{1B}[?1049h"
    /// 端末エミュレータの代替画面から元の画面へ戻る。
    public static let exitAlternateScreen = "\u{1B}[?1049l"

    /// クリック・ドラッグ・ホイールを SGR 拡張形式（1006）で受け取る。
    public static let enableMouseTracking = "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1006h"
    /// ボタンを押していない間の移動（1003）も SGR 拡張形式で受け取る。
    public static let enableMouseMotionTracking = "\u{1B}[?1000h\u{1B}[?1002h\u{1B}[?1003h\u{1B}[?1006h"
    /// マウスの通知（1000 / 1002 / 1003 / 1006）をすべて止める。
    ///
    /// - Note: それぞれ独立した DECSET モードなので、一部を送り直しても他は落ちない。
    ///   範囲を狭めるときは、`ANSI.disableMouseTracking` を送ってから入れ直す。
    /// - See: [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html) の「Mouse Tracking」。
    public static let disableMouseTracking = "\u{1B}[?1006l\u{1B}[?1003l\u{1B}[?1002l\u{1B}[?1000l"

    /// 貼り付けを `ESC [ 200 ~` と `ESC [ 201 ~` で囲んで受け取る。
    public static let enableBracketedPaste = "\u{1B}[?2004h"
    /// ブラケットペーストの通知を止める。
    public static let disableBracketedPaste = "\u{1B}[?2004l"

    /// 同期出力（DECSET 2026）を開始し、終了するまで画面の更新を保留させる。
    ///
    /// - Note: 対応しない端末エミュレータは `ANSI.beginSynchronizedUpdate` を読み飛ばすため、
    ///   送っても表示は変わらない。
    public static let beginSynchronizedUpdate = "\u{1B}[?2026h"
    /// 同期出力を終了し、保留していた更新をまとめて表示させる。
    public static let endSynchronizedUpdate = "\u{1B}[?2026l"

    /// 今のウィンドウタイトルとアイコン名を端末エミュレータのスタックへ積む。
    ///
    /// - Note: タイトルのスタックに対応しない端末エミュレータは `ANSI.saveWindowTitle` を
    ///   読み飛ばすため、積まれない。
    public static let saveWindowTitle = "\u{1B}[22;0t"
    /// 端末エミュレータのスタックからウィンドウタイトルとアイコン名を戻す。
    ///
    /// - Note: スタックが空なら何も起きない。
    public static let restoreWindowTitle = "\u{1B}[23;0t"

    /// 端末エミュレータのフォーカス変化を受け取る。
    public static let enableFocusReporting = "\u{1B}[?1004h"
    /// フォーカス変化の通知を止める。
    public static let disableFocusReporting = "\u{1B}[?1004l"

    /// kitty keyboard protocol の対応状況を問い合わせる。
    ///
    /// - Note: 対応する端末エミュレータだけが `CSI ? <flags> u` のバイト列を送ってくる。
    ///   対応しない端末エミュレータは何も送ってこない。
    public static let queryKeyboardProtocol = "\u{1B}[?u"
    /// 端末エミュレータの種別を問い合わせる。
    ///
    /// - Note: どの端末エミュレータも `CSI ? <params> c` のバイト列を送ってくるため、
    ///   先に送った問い合わせの応答が出揃ったことを知る目印に使える。
    public static let queryDeviceAttributes = "\u{1B}[c"

    /// キーの曖昧さを解消する形式（kitty keyboard protocol の flag 1）でキーを受け取る。
    public static let enableKeyboardProtocol = "\u{1B}[=1u"
    /// kitty keyboard protocol のすべてのフラグを落とし、従来の形式へ戻す。
    public static let disableKeyboardProtocol = "\u{1B}[=0u"

    /// クリップボードへ渡せる Base64 の長さの上限（バイト）。
    ///
    /// - Note: 受け付ける長さは端末エミュレータごとに違い、OSC 52 の仕様にも定めがない。
    public static let clipboardLimit = 100_000

    /// ウィンドウタイトルとアイコン名を設定する、`hasPrefix(ANSI.osc)` が `true` の `String` を組み立てる。
    ///
    /// - Parameters:
    ///   - title: 設定するタイトル。
    /// - Returns: タイトルを設定する `String`。
    /// - Note: `title` の制御文字は取り除く。
    public static func setWindowTitle(_ title: String) -> String {
        let scalars = title.unicodeScalars.filter { $0.properties.generalCategory != .control }
        return osc + "0;" + String(String.UnicodeScalarView(scalars)) + bell
    }

    /// カーソルの形を設定する、`hasPrefix(ANSI.csi)` が `true` の `String` を組み立てる。
    ///
    /// - Parameters:
    ///   - shape: 設定する形。
    /// - Returns: カーソルの形を設定する `String`。
    public static func setCursorShape(_ shape: CursorShape) -> String {
        "\u{1B}[\(shape.parameter) q"
    }

    /// カーソルを移動する、`hasPrefix(ANSI.csi)` が `true` の `String` を組み立てる。
    ///
    /// - Parameters:
    ///   - row: 移動先の行。1 起点。1 未満は 1 に丸める。
    ///   - column: 移動先の列。左端が 1（`Point.x` に 1 を足した値）。1 未満は 1 に丸める。
    /// - Returns: カーソルを移動する `String`。
    public static func moveCursor(row: Int, column: Int) -> String {
        "\u{1B}[\(max(1, row));\(max(1, column))H"
    }

    /// 文字列をクリップボードへ書き込む、`hasPrefix(ANSI.osc)` が `true` の `String`（OSC 52）を組み立てる。
    ///
    /// - Parameters:
    ///   - text: クリップボードへ渡す文字列。空文字列を渡すとクリップボードを空にする。
    ///   - limit: Base64 に変換した後の長さの上限（バイト）。
    /// - Returns: クリップボードへ書き込む `String`。上限を超えるなら `nil`。
    /// - Note: OSC 52 をデフォルトで拒否する端末エミュレータがある（xterm の `allowWindowOps`、
    ///   tmux の `set-clipboard`）。端末エミュレータは応答を送ってこないため、書き込めたかは
    ///   TUIKit アプリから判別できない。
    public static func setClipboard(_ text: String, limit: Int = ANSI.clipboardLimit) -> String? {
        let encoded = Base64.encode(text)
        guard encoded.utf8.count <= limit else { return nil }
        return "\u{1B}]52;c;\(encoded)\u{07}"
    }
}
