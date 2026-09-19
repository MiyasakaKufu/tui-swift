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

    private var originalAttributes: termios?
    private var pendingOutput: [UInt8] = []

    private var isInAlternateScreen = false
    private var isMouseTrackingEnabled = false
    private var isBracketedPasteEnabled = false

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
        originalAttributes != nil
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
    public func enableRawMode() throws {
        guard isTerminal else { throw TerminalError.notATerminal }
        guard originalAttributes == nil else { return }

        var attributes = termios()
        if tcgetattr(inputDescriptor, &attributes) != 0 {
            throw TerminalError.termiosFailed(errno: errno)
        }
        originalAttributes = attributes

        var raw = attributes
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
            originalAttributes = nil
            throw TerminalError.termiosFailed(errno: errno)
        }
    }

    /// raw モードを解除し、元の端末属性へ戻す。
    public func disableRawMode() {
        guard var attributes = originalAttributes else { return }
        _ = tcsetattr(inputDescriptor, TCSAFLUSH, &attributes)
        originalAttributes = nil
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

    /// マウスイベントの通知を切り替える。
    ///
    /// - Parameters:
    ///   - enabled: 受け取るなら `true`。
    public func setMouseTrackingEnabled(_ enabled: Bool) {
        guard enabled != isMouseTrackingEnabled else { return }
        isMouseTrackingEnabled = enabled
        write(enabled ? ANSI.enableMouseTracking : ANSI.disableMouseTracking)
        flush()
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

    /// 端末を起動前の状態へ戻す。
    ///
    /// - Note: 二重に呼んでも安全。
    public func restore() {
        setMouseTrackingEnabled(false)
        setBracketedPasteEnabled(false)
        if isInAlternateScreen {
            leaveAlternateScreen()
        }
        write(ANSI.reset)
        write(ANSI.showCursor)
        flush()
        disableRawMode()
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
