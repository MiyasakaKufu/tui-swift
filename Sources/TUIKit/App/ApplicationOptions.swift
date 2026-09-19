/// `Application` の起動時の設定。
public struct ApplicationOptions {
    /// 代替画面バッファへ切り替える（終了時に元の画面が戻る）。
    public var usesAlternateScreen: Bool
    /// マウスイベントを受け取る。
    public var tracksMouse: Bool
    /// ブラケットペーストを有効にする。
    public var usesBracketedPaste: Bool
    /// 入力がなくても一定間隔で再描画する（秒）。`nil` なら入力があるまで待つ。
    public var frameInterval: Double?
    /// `Component` が処理しなかった Ctrl+C でアプリを終了する。
    ///
    /// - Note: raw モードでは `ISIG` を無効にしているため Ctrl+C は SIGINT にならない。
    ///   この設定がなければ、`handle(_:)` が `.quit` を返さないアプリを端末から
    ///   止められなくなる。自前で Ctrl+C を扱うアプリだけ `false` にする。
    public var quitsOnControlC: Bool

    /// 設定を作る。
    ///
    /// - Parameters:
    ///   - usesAlternateScreen: 代替画面バッファへ切り替えるか。
    ///   - tracksMouse: マウスイベントを受け取るか。
    ///   - usesBracketedPaste: ブラケットペーストを有効にするか。
    ///   - frameInterval: 入力がなくても再描画する間隔（秒）。`nil` なら入力があるまで待つ。
    ///   - quitsOnControlC: 処理されなかった Ctrl+C で終了するか。
    public init(
        usesAlternateScreen: Bool = true,
        tracksMouse: Bool = false,
        usesBracketedPaste: Bool = true,
        frameInterval: Double? = nil,
        quitsOnControlC: Bool = true
    ) {
        self.usesAlternateScreen = usesAlternateScreen
        self.tracksMouse = tracksMouse
        self.usesBracketedPaste = usesBracketedPaste
        self.frameInterval = frameInterval
        self.quitsOnControlC = quitsOnControlC
    }

    /// すべて既定値の設定。
    public static let `default` = ApplicationOptions()

    /// `Component` が処理しなかったイベントで終了するかを判定する。
    ///
    /// - Parameters:
    ///   - event: 処理されなかったイベント。
    /// - Returns: このイベントで終了するなら `true`。
    func quits(onUnhandled event: InputEvent) -> Bool {
        guard quitsOnControlC, case .key(let keyEvent) = event else { return false }
        return keyEvent.isControl("c")
    }
}
