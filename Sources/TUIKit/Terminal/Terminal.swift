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
    public let inputDescriptor: Int32
    public let outputDescriptor: Int32

    private var originalAttributes: termios?
    private var pendingOutput: [UInt8] = []

    private var isInAlternateScreen = false
    private var isMouseTrackingEnabled = false
    private var isBracketedPasteEnabled = false

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

    /// 現在の端末サイズ。取得できない場合は環境変数、それも無ければ 80x24 を返す。
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

    private func environmentInt(_ name: String) -> Int? {
        guard let raw = getenv(name) else { return nil }
        return Int(String(cString: raw))
    }

    // MARK: - raw モード

    /// canonical モードとエコーを無効にし、1 バイトずつ入力を受け取れるようにする。
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

    public func enterAlternateScreen() {
        guard !isInAlternateScreen else { return }
        isInAlternateScreen = true
        write(ANSI.enterAlternateScreen)
        write(ANSI.clearScreen)
        flush()
    }

    public func leaveAlternateScreen() {
        guard isInAlternateScreen else { return }
        isInAlternateScreen = false
        write(ANSI.exitAlternateScreen)
        flush()
    }

    public func setCursorVisible(_ visible: Bool) {
        write(visible ? ANSI.showCursor : ANSI.hideCursor)
        flush()
    }

    public func setMouseTrackingEnabled(_ enabled: Bool) {
        guard enabled != isMouseTrackingEnabled else { return }
        isMouseTrackingEnabled = enabled
        write(enabled ? ANSI.enableMouseTracking : ANSI.disableMouseTracking)
        flush()
    }

    public func setBracketedPasteEnabled(_ enabled: Bool) {
        guard enabled != isBracketedPasteEnabled else { return }
        isBracketedPasteEnabled = enabled
        write(enabled ? ANSI.enableBracketedPaste : ANSI.disableBracketedPaste)
        flush()
    }

    /// 端末を起動前の状態へ戻す。二重に呼んでも安全。
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

    public func write(_ text: String) {
        pendingOutput.append(contentsOf: Array(text.utf8))
    }

    public func flush() {
        guard !pendingOutput.isEmpty else { return }
        let bytes = pendingOutput
        pendingOutput.removeAll(keepingCapacity: true)
        writeAllBytes(outputDescriptor, bytes)
    }
}

/// `write(2)` を最後まで書き切るまで繰り返す。
///
/// `Terminal.write(_:)` と名前が衝突しないよう、ファイルスコープの関数として定義している。
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
