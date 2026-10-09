/// `Application` の起動時の設定。
public struct ApplicationOptions: Sendable {
    /// 端末エミュレータの代替画面（alternate screen）へ切り替える（終了時に元の画面が戻る）。
    public var usesAlternateScreen: Bool
    /// マウスイベントを受け取る範囲。
    ///
    /// - Note: イニシャライザの `mouseTracking:` 引数を省くと `.disabled` で、受け取らない。有効にしない限り `.mouse` は届かない。
    public var mouseTracking: MouseTracking
    /// ブラケットペーストを有効にする。
    public var usesBracketedPaste: Bool
    /// 端末エミュレータのフォーカス変化を `.focus` として受け取る。
    ///
    /// - Note: イニシャライザの `reportsFocus:` 引数を省くと `false`。有効にしない限り `.focus` は届かない。
    ///   フォーカス通知に対応しない端末エミュレータでは、有効にしても届かない。
    public var reportsFocus: Bool
    /// 端末エミュレータが対応していれば kitty keyboard protocol を使う。
    ///
    /// - Note: 有効にすると、起動時に端末エミュレータへ対応状況を問い合わせる。
    ///   対応していれば Ctrl+I と Tab、Ctrl+M と Enter が区別でき、Escape や Alt+[ を
    ///   時間切れで確定させる待ちがなくなる。対応していなければ、従来どおり時間切れで確定させる。
    public var usesKeyboardProtocol: Bool
    /// 起動時に設定するウィンドウタイトル。`nil` なら端末エミュレータのウィンドウタイトルを変えない。
    ///
    /// - Note: 終了時と一時停止時に、設定する前のタイトルへ戻す。
    ///   タイトルのスタックに対応しない端末エミュレータでは戻らない。
    public var windowTitle: String?
    /// 起動時に設定するカーソル形状。`nil` なら端末エミュレータの設定どおりの形にする。
    ///
    /// - Note: 終了時と一時停止時に、端末エミュレータの設定どおりの形へ戻す。
    public var cursorShape: CursorShape?
    /// 入力がなくても一定間隔で再描画する（秒）。`nil` なら入力があるまで待つ。
    public var frameInterval: Double?
    /// `Component.handle(_:)` が `.ignored` を返した Ctrl+C で `Application` を終了する。
    ///
    /// - Note: raw モードでは `ISIG` を無効にしているため Ctrl+C は SIGINT にならない。
    ///   この設定がなければ、`Component.handle(_:)` が `.quit` を返さない TUIKit アプリを
    ///   端末エミュレータから止められなくなる。
    ///   `Component.handle(_:)` で Ctrl+C を扱う TUIKit アプリだけ `false` にする。
    public var quitsOnControlC: Bool
    /// `Component.handle(_:)` が `.ignored` を返した Ctrl+Z で TUIKit アプリを一時停止する。
    ///
    /// - Note: raw モードでは `ISIG` を無効にしているため Ctrl+Z は SIGTSTP にならない。
    ///   この設定がなければ、端末デバイスの termios と、端末エミュレータへ送ったモードを戻さないまま止まるか、
    ///   そもそも止まらない。`Component.handle(_:)` で Ctrl+Z を扱う TUIKit アプリだけ `false` にする。
    public var suspendsOnControlZ: Bool
    /// East Asian Width が Ambiguous の文字を `Cell` 何個分として扱うか。
    ///
    /// - Note: 端末エミュレータの設定と食い違うと、罫線素片や `…` を含む行で、後ろに続く文字が横にずれる。
    ///   イニシャライザの `ambiguousWidth:` 引数を省くと `DisplayWidth.defaultAmbiguousWidth`（環境変数 `RUNEWIDTH_EASTASIAN` から決まる）。
    public var ambiguousWidth: DisplayWidth.AmbiguousWidth

    /// 設定を作る。
    ///
    /// - Parameters:
    ///   - usesAlternateScreen: 端末エミュレータの代替画面へ切り替えるか。
    ///   - mouseTracking: マウスイベントを受け取る範囲。
    ///   - usesBracketedPaste: ブラケットペーストを有効にするか。
    ///   - reportsFocus: 端末エミュレータのフォーカス変化を受け取るか。
    ///   - usesKeyboardProtocol: 端末エミュレータが対応していれば kitty keyboard protocol を使うか。
    ///   - windowTitle: 起動時に設定するウィンドウタイトル。`nil` なら変えない。
    ///   - cursorShape: 起動時に設定するカーソル形状。`nil` なら変えない。
    ///   - frameInterval: 入力がなくても再描画する間隔（秒）。`nil` なら入力があるまで待つ。
    ///   - quitsOnControlC: `Component.handle(_:)` が `.ignored` を返した Ctrl+C で終了するか。
    ///   - suspendsOnControlZ: `Component.handle(_:)` が `.ignored` を返した Ctrl+Z で一時停止するか。
    ///   - ambiguousWidth: East Asian Width が Ambiguous の文字を `Cell` 何個分として扱うか。
    public init(
        usesAlternateScreen: Bool = true,
        mouseTracking: MouseTracking = .disabled,
        usesBracketedPaste: Bool = true,
        reportsFocus: Bool = false,
        usesKeyboardProtocol: Bool = true,
        windowTitle: String? = nil,
        cursorShape: CursorShape? = nil,
        frameInterval: Double? = nil,
        quitsOnControlC: Bool = true,
        suspendsOnControlZ: Bool = true,
        ambiguousWidth: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) {
        self.usesAlternateScreen = usesAlternateScreen
        self.mouseTracking = mouseTracking
        self.usesBracketedPaste = usesBracketedPaste
        self.reportsFocus = reportsFocus
        self.usesKeyboardProtocol = usesKeyboardProtocol
        self.windowTitle = windowTitle
        self.cursorShape = cursorShape
        self.frameInterval = frameInterval
        self.quitsOnControlC = quitsOnControlC
        self.suspendsOnControlZ = suspendsOnControlZ
        self.ambiguousWidth = ambiguousWidth
    }

    /// イニシャライザの引数をすべて省いて作った `ApplicationOptions`。
    public static let `default` = ApplicationOptions()

    /// `Component.handle(_:)` が `.ignored` を返した `InputEvent` で終了するかを判定する。
    ///
    /// - Parameters:
    ///   - event: `Component.handle(_:)` が `.ignored` を返した `InputEvent`。
    /// - Returns: このイベントで終了するなら `true`。
    func quits(onUnhandled event: InputEvent) -> Bool {
        guard quitsOnControlC, case .key(let keyEvent) = event else { return false }
        return keyEvent.isControl("c")
    }

    /// `Component.handle(_:)` が `.ignored` を返した `InputEvent` で一時停止するかを判定する。
    ///
    /// - Parameters:
    ///   - event: `Component.handle(_:)` が `.ignored` を返した `InputEvent`。
    /// - Returns: このイベントで一時停止するなら `true`。
    func suspends(onUnhandled event: InputEvent) -> Bool {
        guard suspendsOnControlZ, case .key(let keyEvent) = event else { return false }
        return keyEvent.isControl("z")
    }
}
