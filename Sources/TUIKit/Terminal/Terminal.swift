#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CTUIShim

/// 端末制御に失敗したときのエラー。
public enum TerminalError: Error, Equatable {
    /// 標準入出力が端末に接続されていない。
    case notATerminal
    /// termios の取得・設定に失敗した。
    case termiosFailed(errno: Int32)
    /// 端末サイズの取得に失敗した。
    case sizeUnavailable
}

/// 端末そのものを表し、raw モードや代替画面の切り替えと出力を担当する。
public final class Terminal: TerminalOutput {
    /// 入力を読み取るファイル記述子。
    public let inputDescriptor: Int32
    /// 出力を書き出すファイル記述子。
    public let outputDescriptor: Int32

    /// raw モードへ入る前の端末属性。戻す先として覚えておく。
    private var originalAttributes: termios?
    /// raw モードが今この端末に効いているか。
    private var isRawModeActive = false
    private var pendingOutput: [UInt8] = []

    private var isInAlternateScreen = false
    private var mouseTracking: MouseTracking = .disabled
    private var isBracketedPasteEnabled = false
    private var isFocusReportingEnabled = false
    private var isKeyboardProtocolEnabled = false
    private var windowTitle: String?
    private var cursorShape: CursorShape?

    /// 入出力のファイル記述子を指定して端末を作る。
    ///
    /// - Parameters:
    ///   - input: 入力を読み取るファイル記述子。
    ///   - output: 出力を書き出すファイル記述子。
    public init(input: Int32 = 0, output: Int32 = 1) {
        self.inputDescriptor = input
        self.outputDescriptor = output
    }

    deinit {
        restore()
    }

    /// 入出力の両方が端末に接続されているか。
    public var isTerminal: Bool {
        isatty(inputDescriptor) == 1 && isatty(outputDescriptor) == 1
    }

    /// raw モードが有効かどうか。
    public var isRawModeEnabled: Bool {
        isRawModeActive
    }

    // MARK: - サイズ

    /// 現在の端末サイズを問い合わせる。
    ///
    /// - Returns: 端末サイズ。問い合わせに失敗した場合は環境変数 `COLUMNS` / `LINES`、
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
    /// - Throws: 入出力が端末でなければ `TerminalError.notATerminal`、
    ///   termios の取得・設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    /// - Postcondition: 元の端末属性を覚えるため、`disableRawMode()` で戻せる。
    ///   すでに raw モードなら何もしない。
    /// - Note: クラッシュしても端末が戻るよう、シグナルハンドラを仕掛ける。
    public func enableRawMode() throws {
        guard isTerminal else { throw TerminalError.notATerminal }
        guard !isRawModeActive else { return }

        var attributes = termios()
        if tcgetattr(inputDescriptor, &attributes) != 0 {
            throw TerminalError.termiosFailed(errno: errno)
        }
        try applyRawMode(basedOn: attributes)
    }

    /// 覚えた端末属性をもとに raw モードを設定する。
    ///
    /// - Parameters:
    ///   - original: raw モードへ入る前の端末属性。
    /// - Throws: termios の設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    private func applyRawMode(basedOn original: termios) throws {
        var raw = original
        raw.c_iflag &= ~tcflag_t(IXON | ICRNL | BRKINT | INPCK | ISTRIP)
        raw.c_oflag &= ~tcflag_t(OPOST)
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG | IEXTEN)
        raw.c_cflag |= tcflag_t(CS8)

        // poll(2) で待つので、read(2) 自体は即座に返るようにしておく。
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

    /// raw モードを解除し、元の端末属性へ戻す。
    public func disableRawMode() {
        applyOriginalAttributes()
        originalAttributes = nil
        CrashRestorer.disarm()
    }

    /// 覚えている端末属性を書き戻す。
    ///
    /// - Postcondition: 覚えた属性は残るので、`reactivate()` で raw モードへ戻せる。
    private func applyOriginalAttributes() {
        guard isRawModeActive, var attributes = originalAttributes else { return }
        _ = tcsetattr(inputDescriptor, TCSAFLUSH, &attributes)
        isRawModeActive = false
    }

    // MARK: - 画面モード

    /// 代替画面バッファへ切り替え、画面を消す。
    public func enterAlternateScreen() {
        guard !isInAlternateScreen else { return }
        isInAlternateScreen = true
        write(ANSI.enterAlternateScreen)
        write(ANSI.clearScreen)
        flush()
    }

    /// 代替画面バッファから元の画面へ戻る。
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
    /// - Note: タイトルのスタックに対応しない端末では、設定はできても戻らない。
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
    /// - Postcondition: `restore()` / `deactivate()` で端末の設定どおりの形へ戻る。
    /// - Note: `DECSCUSR` に対応しない端末では何も変わらない。
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
        // 1003 は 1000 や 1002 を送り直しても落ちない。この行を外して新しい範囲を送るだけに
        // すると、`.motion` から狭めたときに移動の通知が残る。
        if mouseTracking != .disabled { write(ANSI.disableMouseTracking) }
        mouseTracking = tracking
        if let sequence = Terminal.enableSequence(for: tracking) { write(sequence) }
        flush()
    }

    /// マウスイベントを受け取る範囲を端末へ伝えるシーケンスを返す。
    ///
    /// - Parameters:
    ///   - tracking: 受け取る範囲。
    /// - Returns: 端末へ送るシーケンス。`.disabled` なら `nil`。
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
    /// - Note: 有効にすると、端末がフォーカスを得たとき `ESC [ I`、失ったとき `ESC [ O` を
    ///   送ってくる。`InputParser` はこれらを `.focus` として解釈する。
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
    /// - Note: 対応しない端末は制御コードを読み飛ばすため、有効にしても何も変わらない。
    ///   対応しているかは `ANSI.queryKeyboardProtocol` で問い合わせる。
    public func setKeyboardProtocolEnabled(_ enabled: Bool) {
        guard enabled != isKeyboardProtocolEnabled else { return }
        isKeyboardProtocolEnabled = enabled
        write(enabled ? ANSI.enableKeyboardProtocol : ANSI.disableKeyboardProtocol)
        flush()
    }

    /// 端末を起動前の状態へ戻す。
    ///
    /// - Note: 二重に呼んでも安全。
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

    /// 設定を覚えたまま端末を起動前の状態へ戻す。
    ///
    /// 一時停止のように、端末をいったんシェルへ返してから戻ってくる場合に使う。
    ///
    /// - Postcondition: `reactivate()` で同じ設定へ戻せる。二重に呼んでも安全。
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

    /// 覚えている設定を端末へ入れ直す。
    ///
    /// - Throws: 入出力が端末でなければ `TerminalError.notATerminal`、
    ///   termios の設定に失敗すれば `TerminalError.termiosFailed(errno:)`。
    /// - Note: `deactivate()` の後だけでなく、捕まえられない SIGSTOP で止められた後のように、
    ///   端末側の設定だけが失われた場合にも使える。今の状態を見ずに必ず設定し直す。
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

    /// 文字列をクリップボードへ渡す。
    ///
    /// - Parameters:
    ///   - text: クリップボードへ渡す文字列。空文字列を渡すとクリップボードを空にする。
    ///   - limit: Base64 に変換した後の長さの上限（バイト）。
    /// - Returns: 端末へ送ったなら `true`。上限を超えて送らなかったなら `false`。
    /// - Note: 端末が OSC 52 を拒否していれば、送ってもクリップボードは変わらない。
    ///   応答がないため、戻り値では区別できない。
    @discardableResult
    public func copyToClipboard(_ text: String, limit: Int = ANSI.clipboardLimit) -> Bool {
        guard let sequence = ANSI.setClipboard(text, limit: limit) else { return false }
        write(sequence)
        flush()
        return true
    }

    // MARK: - 出力

    /// 文字列を出力バッファへ追加する。
    ///
    /// - Parameters:
    ///   - text: 追加する文字列。
    public func write(_ text: String) {
        pendingOutput.append(contentsOf: Array(text.utf8))
    }

    /// 溜めた出力を端末へ書き出す。
    public func flush() {
        guard !pendingOutput.isEmpty else { return }
        let bytes = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        writeAllBytes(outputDescriptor, bytes)
    }
}

// `Terminal` のメソッドにしてはいけない。`Terminal.write(_:)` が先に見つかり、
// 自分自身を呼び続ける。

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
