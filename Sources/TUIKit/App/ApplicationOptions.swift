/// `Application` の起動時の設定。
public struct ApplicationOptions {
    /// 代替画面バッファへ切り替える（終了時に元の画面が戻る）。
    public var usesAlternateScreen: Bool
    /// マウスイベントを受け取る。
    public var tracksMouse: Bool
    /// ブラケットペーストを有効にする。
    public var usesBracketedPaste: Bool
    /// 端末のフォーカス変化を `.focus` として受け取る。
    ///
    /// - Note: 既定では無効。有効にしない限り `.focus` は届かない。
    ///   フォーカス通知に対応しない端末では、有効にしても届かない。
    public var reportsFocus: Bool
    /// 端末が対応していれば kitty keyboard protocol を使う。
    ///
    /// - Note: 有効にすると、起動時に端末へ対応状況を問い合わせる。
    ///   対応していれば Ctrl+I と Tab、Ctrl+M と Enter が区別でき、Escape や Alt+[ を
    ///   時間切れで確定させる待ちがなくなる。対応していなければ、従来どおり時間切れで確定させる。
    public var usesKeyboardProtocol: Bool
    /// 起動時に設定するウィンドウタイトル。`nil` なら端末のタイトルを変えない。
    ///
    /// - Note: 終了時と一時停止時に、設定する前のタイトルへ戻す。
    ///   タイトルのスタックに対応しない端末では戻らない。
    public var windowTitle: String?
    /// 起動時に設定するカーソル形状。`nil` なら端末の設定どおりの形にする。
    ///
    /// - Note: 終了時と一時停止時に、端末の設定どおりの形へ戻す。
    public var cursorShape: CursorShape?
    /// 入力がなくても一定間隔で再描画する（秒）。`nil` なら入力があるまで待つ。
    public var frameInterval: Double?
    /// `Component` が処理しなかった Ctrl+C でアプリを終了する。
    ///
    /// - Note: raw モードでは `ISIG` を無効にしているため Ctrl+C は SIGINT にならない。
    ///   この設定がなければ、`handle(_:)` が `.quit` を返さないアプリを端末から
    ///   止められなくなる。自前で Ctrl+C を扱うアプリだけ `false` にする。
    public var quitsOnControlC: Bool
    /// `Component` が処理しなかった Ctrl+Z でアプリを一時停止する。
    ///
    /// - Note: raw モードでは `ISIG` を無効にしているため Ctrl+Z は SIGTSTP にならない。
    ///   この設定がなければ、端末を戻さないまま止まるか、そもそも止まらない。
    ///   Ctrl+Z を自前で扱うアプリだけ `false` にする。
    public var suspendsOnControlZ: Bool

    /// 設定を作る。
    ///
    /// - Parameters:
    ///   - usesAlternateScreen: 代替画面バッファへ切り替えるか。
    ///   - tracksMouse: マウスイベントを受け取るか。
    ///   - usesBracketedPaste: ブラケットペーストを有効にするか。
    ///   - reportsFocus: 端末のフォーカス変化を受け取るか。
    ///   - usesKeyboardProtocol: 端末が対応していれば kitty keyboard protocol を使うか。
    ///   - windowTitle: 起動時に設定するウィンドウタイトル。`nil` なら変えない。
    ///   - cursorShape: 起動時に設定するカーソル形状。`nil` なら変えない。
    ///   - frameInterval: 入力がなくても再描画する間隔（秒）。`nil` なら入力があるまで待つ。
    ///   - quitsOnControlC: 処理されなかった Ctrl+C で終了するか。
    ///   - suspendsOnControlZ: 処理されなかった Ctrl+Z で一時停止するか。
    public init(
        usesAlternateScreen: Bool = true,
        tracksMouse: Bool = false,
        usesBracketedPaste: Bool = true,
        reportsFocus: Bool = false,
        usesKeyboardProtocol: Bool = true,
        windowTitle: String? = nil,
        cursorShape: CursorShape? = nil,
        frameInterval: Double? = nil,
        quitsOnControlC: Bool = true,
        suspendsOnControlZ: Bool = true
    ) {
        self.usesAlternateScreen = usesAlternateScreen
        self.tracksMouse = tracksMouse
        self.usesBracketedPaste = usesBracketedPaste
        self.reportsFocus = reportsFocus
        self.usesKeyboardProtocol = usesKeyboardProtocol
        self.windowTitle = windowTitle
        self.cursorShape = cursorShape
        self.frameInterval = frameInterval
        self.quitsOnControlC = quitsOnControlC
        self.suspendsOnControlZ = suspendsOnControlZ
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

    /// `Component` が処理しなかったイベントで一時停止するかを判定する。
    ///
    /// - Parameters:
    ///   - event: 処理されなかったイベント。
    /// - Returns: このイベントで一時停止するなら `true`。
    func suspends(onUnhandled event: InputEvent) -> Bool {
        guard suspendsOnControlZ, case .key(let keyEvent) = event else { return false }
        return keyEvent.isControl("z")
    }
}
