#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CTUIShim

/// `Terminal` が端末デバイスを操作できなかったときのエラー。
public enum TerminalError: Error, Equatable {
    /// `Terminal.inputDescriptor` か `Terminal.outputDescriptor` が端末デバイスでない。
    case notATerminal
    /// 端末デバイスの termios の取得・設定に失敗した。
    case termiosFailed(errno: Int32)
    /// 端末デバイスのウィンドウサイズの取得に失敗した。
    case sizeUnavailable
}

/// 端末デバイスへの書き出しと termios の書き換え、端末エミュレータへ送るモードの切り替えを行う型。
@MainActor
public final class Terminal: TerminalOutput {
    /// 入力を読み取るファイル記述子。
    public let inputDescriptor: Int32
    /// 出力を書き出すファイル記述子。
    public let outputDescriptor: Int32

    /// raw モードへ入る前の、端末デバイスの termios。戻す先として覚えておく。
    private var originalAttributes: termios?
    /// raw モードが今この端末デバイスに効いているか。
    private var isRawModeActive = false
    private var pendingOutput: [UInt8] = []

    private var isInAlternateScreen = false
    private var mouseTracking: MouseTracking = .disabled
    private var isBracketedPasteEnabled = false
    private var isFocusReportingEnabled = false
    private var isKeyboardProtocolEnabled = false
    private var windowTitle: String?
    private var cursorShape: CursorShape?

    /// 入出力のファイル記述子を指定して `Terminal` を作る。
    ///
    /// - Parameters:
    ///   - input: 入力を読み取るファイル記述子。
    ///   - output: 出力を書き出すファイル記述子。
    public init(input: Int32 = 0, output: Int32 = 1) {
        self.inputDescriptor = input
        self.outputDescriptor = output
    }

    /// 入出力の両方が端末デバイスに接続されているか。
    public var isTerminal: Bool {
        isatty(inputDescriptor) == 1 && isatty(outputDescriptor) == 1
    }

    /// raw モードが有効かどうか。
    public var isRawModeEnabled: Bool {
        isRawModeActive
    }

    // MARK: - サイズ

    /// 端末デバイスの現在のウィンドウサイズを問い合わせる。
    ///
    /// - Returns: 端末デバイスのウィンドウサイズ。問い合わせに失敗した場合は環境変数 `COLUMNS` / `LINES`、
    ///   それも無ければ 80x24。
    public func size() -> Size {
        var columns: Int32 = 0
        var rows: Int32 = 0
        if ctui_terminal_size(outputDescriptor, &columns, &rows) == 0, columns > 0, rows > 0 {
            return Size(width: Int(columns), height: Int(rows))
        }
        let fallbackColumns = environmentInt("COLUMNS") ?? 80
        let fallbackRows = environmentInt("LINES") ?? 24
        return Size(width: fallbackColumns, height: fallbackRows)
    }

    /// 環境変数の値を整数として読む。
    ///
    /// - Parameters:
    ///   - name: 環境変数の名前。
    /// - Returns: 整数として読めた値。未設定か整数でなければ `nil`。
    private func environmentInt(_ name: String) -> Int? {
        guard let raw = getenv(name) else { return nil }
        return Int(String(cString: raw))
    }

    // MARK: - raw モード

    /// canonical モードとエコーを無効にし、1 バイトずつ入力を受け取れるようにする。
    ///
    /// - Throws: 入出力が端末デバイスでなければ `TerminalError.notATerminal`、
    ///   termios の取得・設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    /// - Postcondition: raw モードへ入る前の termios を覚えるため、`disableRawMode()` で戻せる。
    ///   すでに raw モードなら何もしない。
    /// - Note: クラッシュしても端末デバイスの termios と、端末エミュレータへ送ったモードが戻るよう、
    ///   シグナルハンドラを仕掛ける。
    /// - Note: `restore()` を呼び出さずにこの `Terminal` を捨てた場合、
    ///   端末デバイスの termios が戻り、端末エミュレータへ送ったモードを戻す `String` が書き出されるのは、
    ///   プロセスが終わるときになる。その前に別の `Terminal` が raw モードへ入るか、
    ///   `disableRawMode()`（`restore()` からも呼び出される）を呼び出すと戻らない。
    ///   戻す先は 1 組しか覚えておけないため。捨てる前に `restore()` を呼び出すこと。
    ///   入出力のファイル記述子を閉じる前にも `restore()` を呼び出すこと。呼び出さずに閉じると、
    ///   プロセスが終わるときに、同じ番号を割り当てられた別のファイルへ
    ///   モードを戻す `String` を書き込み、termios を設定しようとする。
    public func enableRawMode() throws {
        guard isTerminal else { throw TerminalError.notATerminal }
        guard !isRawModeActive else { return }

        var attributes = termios()
        if tcgetattr(inputDescriptor, &attributes) != 0 {
            throw TerminalError.termiosFailed(errno: errno)
        }
        try applyRawMode(basedOn: attributes)
    }

    /// `original` をもとに、端末デバイスの termios を raw モードへ書き換える。
    ///
    /// - Parameters:
    ///   - original: raw モードへ入る前の、端末デバイスの termios。
    /// - Throws: termios の設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    private func applyRawMode(basedOn original: termios) throws {
        var raw = original
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_cflag |= tcflag_t(CS8)

        // `VMIN` を 1 に戻してはいけない。待つのは `poll(2)` の役目で、`read(2)` が入力を
        // 待つと、シグナルの合図で起こしても読み終えるまで戻らない。
        withUnsafeMutablePointer(to: &raw.c_cc) { pointer in
            pointer.withMemoryRebound(to: cc_t.self, capacity: Int(NCCS)) { controlCharacters in
                controlCharacters[Int(VMIN)] = 0
                controlCharacters[Int(VTIME)] = 0
            }
        }

        if tcsetattr(inputDescriptor, TCSAFLUSH, &raw) != 0 {
            throw TerminalError.termiosFailed(errno: errno)
        }

        originalAttributes = original
        isRawModeActive = true
        CrashRestorer.arm(
            input: inputDescriptor,
            output: outputDescriptor,
            originalAttributes: original
        )
    }

    /// raw モードを解除し、端末デバイスの termios を元へ戻す。
    public func disableRawMode() {
        applyOriginalAttributes()
        originalAttributes = nil
        CrashRestorer.disarm()
    }

    /// 覚えている termios を端末デバイスへ書き戻す。
    ///
    /// - Postcondition: 覚えた termios は残るので、`reactivate()` で raw モードへ戻せる。
    private func applyOriginalAttributes() {
        guard isRawModeActive, var attributes = originalAttributes else { return }
        _ = tcsetattr(inputDescriptor, TCSAFLUSH, &attributes)
        isRawModeActive = false
    }

    // MARK: - 画面モード

    /// 端末エミュレータの代替画面（alternate screen）へ切り替え、画面を消す。
    public func enterAlternateScreen() {
        guard !isInAlternateScreen else { return }
        isInAlternateScreen = true
        write(ANSI.enterAlternateScreen)
        write(ANSI.clearScreen)
        flush()
    }

    /// 端末エミュレータの代替画面から元の画面へ戻る。
    public func leaveAlternateScreen() {
        guard isInAlternateScreen else { return }
        isInAlternateScreen = false
        write(ANSI.exitAlternateScreen)
        flush()
    }

    /// カーソルの表示を切り替える。
    ///
    /// - Parameters:
    ///   - visible: 表示するなら `true`。
    public func setCursorVisible(_ visible: Bool) {
        write(visible ? ANSI.showCursor : ANSI.hideCursor)
        flush()
    }

    /// ウィンドウタイトルとアイコン名を設定する。
    ///
    /// - Parameters:
    ///   - title: 設定するタイトル。
    /// - Postcondition: `restore()` / `deactivate()` で設定する前のタイトルへ戻る。
    /// - Note: タイトルのスタックに対応しない端末エミュレータでは、設定はできても戻らない。
    public func setWindowTitle(_ title: String) {
        if windowTitle == nil { write(ANSI.saveWindowTitle) }
        windowTitle = title
        write(ANSI.setWindowTitle(title))
        flush()
    }

    /// カーソルの形と点滅の有無を切り替える。
    ///
    /// - Parameters:
    ///   - shape: 設定する形。
    /// - Postcondition: `restore()` / `deactivate()` で端末エミュレータの設定どおりの形へ戻る。
    /// - Note: `DECSCUSR` に対応しない端末エミュレータでは何も変わらない。
    public func setCursorShape(_ shape: CursorShape) {
        guard shape != cursorShape else { return }
        cursorShape = shape
        write(ANSI.setCursorShape(shape))
        flush()
    }

    /// マウスイベントを受け取る範囲を切り替える。
    ///
    /// - Parameters:
    ///   - tracking: 受け取る範囲。
    /// - Note: `.motion` で届く移動を、`InputParser` は `.move` として解釈する。
    public func setMouseTracking(_ tracking: MouseTracking) {
        guard tracking != mouseTracking else { return }
        // この行を外して新しい範囲を送るだけにすると、`.motion` から狭めたときに
        // 移動の通知が残る。
        if mouseTracking != .disabled { write(ANSI.disableMouseTracking) }
        mouseTracking = tracking
        if let sequence = Terminal.enableSequence(for: tracking) { write(sequence) }
        flush()
    }

    /// マウスイベントを受け取る範囲を端末エミュレータへ伝える `ANSI` の定数を返す。
    ///
    /// - Parameters:
    ///   - tracking: 受け取る範囲。
    /// - Returns: `tracking` の範囲を有効にする `ANSI` の定数。`.disabled` なら `nil`。
    private static func enableSequence(for tracking: MouseTracking) -> String? {
        switch tracking {
        case .disabled: return nil
        case .buttons: return ANSI.enableMouseTracking
        case .motion: return ANSI.enableMouseMotionTracking
        }
    }

    /// ブラケットペーストを切り替える。
    ///
    /// - Parameters:
    ///   - enabled: 有効にするなら `true`。
    public func setBracketedPasteEnabled(_ enabled: Bool) {
        guard enabled != isBracketedPasteEnabled else { return }
        isBracketedPasteEnabled = enabled
        write(enabled ? ANSI.enableBracketedPaste : ANSI.disableBracketedPaste)
        flush()
    }

    /// フォーカス通知を切り替える。
    ///
    /// - Parameters:
    ///   - enabled: 受け取るなら `true`。
    /// - Note: 有効にすると、端末エミュレータがフォーカスを得たとき `ESC [ I`、失ったとき
    ///   `ESC [ O` のバイト列を送ってくる。`InputParser` はこれらを `.focus` として解釈する。
    public func setFocusReportingEnabled(_ enabled: Bool) {
        guard enabled != isFocusReportingEnabled else { return }
        isFocusReportingEnabled = enabled
        write(enabled ? ANSI.enableFocusReporting : ANSI.disableFocusReporting)
        flush()
    }

    /// kitty keyboard protocol を切り替える。
    ///
    /// 有効にすると、Ctrl+I と Tab のように従来は同じバイト列になるキーが区別でき、
    /// Escape や Alt+[ の続きを時間切れで待つ必要がなくなる。
    ///
    /// - Parameters:
    ///   - enabled: 有効にするなら `true`。
    /// - Note: 対応しない端末エミュレータは `ANSI.enableKeyboardProtocol` を読み飛ばすため、
    ///   有効にしても何も変わらない。
    ///   対応しているかは `ANSI.queryKeyboardProtocol` で問い合わせる。
    public func setKeyboardProtocolEnabled(_ enabled: Bool) {
        guard enabled != isKeyboardProtocolEnabled else { return }
        isKeyboardProtocolEnabled = enabled
        write(enabled ? ANSI.enableKeyboardProtocol : ANSI.disableKeyboardProtocol)
        flush()
    }

    /// 端末デバイスの termios と、端末エミュレータへ送ったモードを元に戻す。
    ///
    /// - Note: 二重に呼び出しても安全。
    public func restore() {
        deactivate()
        isInAlternateScreen = false
        mouseTracking = .disabled
        isBracketedPasteEnabled = false
        isFocusReportingEnabled = false
        isKeyboardProtocolEnabled = false
        windowTitle = nil
        cursorShape = nil
        disableRawMode()
    }

    /// 端末エミュレータへ送ったモードを覚えたまま、端末デバイスの termios とそのモードを元に戻す。
    ///
    /// 一時停止のように、端末デバイスをいったんシェルに使わせてから戻ってくる場合に使う。
    ///
    /// - Postcondition: `reactivate()` で raw モードと、端末エミュレータへ送ったモードへ戻せる。二重に呼び出しても安全。
    public func deactivate() {
        // 同期出力を開くのは `Renderer` で、この型は開いているかを知らない。開いたまま
        // 抜けると、後ろに続く復元が画面へ出ない。
        write(ANSI.endSynchronizedUpdate)
        if isKeyboardProtocolEnabled { write(ANSI.disableKeyboardProtocol) }
        if mouseTracking != .disabled { write(ANSI.disableMouseTracking) }
        if isBracketedPasteEnabled { write(ANSI.disableBracketedPaste) }
        if isFocusReportingEnabled { write(ANSI.disableFocusReporting) }
        if isInAlternateScreen { write(ANSI.exitAlternateScreen) }
        if cursorShape != nil { write(ANSI.setCursorShape(.default)) }
        if windowTitle != nil { write(ANSI.restoreWindowTitle) }
        write(ANSI.reset)
        write(ANSI.showCursor)
        flush()
        applyOriginalAttributes()
    }

    /// 覚えている termios をもとに端末デバイスを raw モードへ戻し、覚えているモードを端末エミュレータへ送り直す。
    ///
    /// - Throws: 入出力が端末デバイスでなければ `TerminalError.notATerminal`、
    ///   termios の設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    /// - Note: `deactivate()` の後だけでなく、捕まえられない SIGSTOP で止められた後のように、
    ///   端末デバイスの termios や端末エミュレータのモードだけが失われた場合にも使える。
    ///   端末デバイスの termios や端末エミュレータのモードが今どうなっているかは見ずに、毎回 termios を
    ///   書き換え、モードを送り直す。
    public func reactivate() throws {
        guard isTerminal else { throw TerminalError.notATerminal }

        if let original = originalAttributes {
            try applyRawMode(basedOn: original)
        }
        if isInAlternateScreen {
            write(ANSI.enterAlternateScreen)
            write(ANSI.clearScreen)
        }
        if let sequence = Terminal.enableSequence(for: mouseTracking) { write(sequence) }
        if isBracketedPasteEnabled { write(ANSI.enableBracketedPaste) }
        if isFocusReportingEnabled { write(ANSI.enableFocusReporting) }
        if isKeyboardProtocolEnabled { write(ANSI.enableKeyboardProtocol) }
        if let windowTitle {
            write(ANSI.saveWindowTitle)
            write(ANSI.setWindowTitle(windowTitle))
        }
        if let cursorShape { write(ANSI.setCursorShape(cursorShape)) }
        flush()
    }

    // MARK: - クリップボード

    /// 文字列を、端末エミュレータを通してクリップボードへ渡す。
    ///
    /// - Parameters:
    ///   - text: クリップボードへ渡す文字列。空文字列を渡すとクリップボードを空にする。
    ///   - limit: Base64 に変換した後の長さの上限（バイト）。
    /// - Returns: `ANSI.setClipboard(_:limit:)` の戻り値を端末デバイスへ書き出したなら `true`。
    ///   上限を超えて書き出さなかったなら `false`。
    /// - Note: 端末エミュレータが OSC 52 を拒否していれば、書き出してもクリップボードは変わらない。
    ///   端末エミュレータは応答を送ってこないため、戻り値では区別できない。
    @discardableResult
    public func copyToClipboard(_ text: String, limit: Int = ANSI.clipboardLimit) -> Bool {
        guard let sequence = ANSI.setClipboard(text, limit: limit) else { return false }
        write(sequence)
        flush()
        return true
    }

    // MARK: - 出力

    /// 文字列を、`flush()` で端末デバイスへ書き出すまで溜めておく。
    ///
    /// - Parameters:
    ///   - text: 溜めておく文字列。
    public func write(_ text: String) {
        pendingOutput.append(contentsOf: Array(text.utf8))
    }

    /// 溜めた出力を端末デバイスへ書き出す。
    public func flush() {
        guard !pendingOutput.isEmpty else { return }
        let bytes = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        writeAllBytes(outputDescriptor, bytes)
    }
}

// `Terminal` のメソッドにしてはいけない。`Terminal.write(_:)` が先に見つかり、
// 自分自身を呼び出し続ける。

/// `write(2)` を最後まで書き切るまで繰り返す。
///
/// - Parameters:
///   - descriptor: 書き出す先のファイル記述子。
///   - bytes: 書き出すバイト列。
private func writeAllBytes(_ descriptor: Int32, _ bytes: [UInt8]) {
    bytes.withUnsafeBufferPointer { buffer in
        guard let base = buffer.baseAddress else { return }
        var offset = 0
        while offset < buffer.count {
            let written = write(descriptor, base + offset, buffer.count - offset)
            if written > 0 {
                offset += written
            } else if written < 0 && errno == EINTR {
                continue
            } else {
                break
            }
        }
    }
}
