#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 端末を初期化し、入力・描画のループを回すアプリケーション。
public final class Application<Root: Component> {

    private let root: Root
    private let options: ApplicationOptions
    private let terminal: Terminal
    private let reader: InputReader
    private let renderer: Renderer

    private var buffer = Buffer(size: .zero)
    /// 最後に `.resize` として通知したサイズ。
    private var reportedSize = Size.zero
    /// 最後にフレームを数えた時刻。
    private var lastFrameTime = 0.0
    private var isRunning = false

    /// 端末を戻した後にプロセスを止める処理。
    ///
    /// - Note: 実際に止めるとテストプロセスまで止まるため、テストでは差し替える。
    var stopProcess: () -> Void = { SignalWatcher.stopProcess() }

    /// ルートと設定を指定してアプリケーションを作る。
    ///
    /// - Parameters:
    ///   - root: 画面を組み立て、イベントを受け取るルート。
    ///   - options: 起動時の設定。
    ///   - terminal: 使用する端末。テストでは差し替える。
    public init(
        root: Root,
        options: ApplicationOptions = .default,
        terminal: Terminal = Terminal()
    ) {
        self.root = root
        self.options = options
        self.terminal = terminal
        self.reader = InputReader(descriptor: terminal.inputDescriptor)
        self.renderer = Renderer(output: terminal)
    }

    /// ループを終了させる。イベントハンドラの中からも呼べる。
    public func stop() {
        isRunning = false
    }

    /// 端末をシェルへ返してプロセスを止め、再開したら端末を設定し直す。
    ///
    /// raw モードでは `ISIG` を無効にしているため、Ctrl+Z はシグナルにならずキーとして届く。
    /// 一時停止したいアプリは、そのキーを受けたときにこれを呼ぶ。
    ///
    /// - Postcondition: 再開したら画面全体を描き直し、改めて `.resize` を通知する。
    /// - Note: `ApplicationOptions.suspendsOnControlZ` が有効なら、
    ///   ルートが処理しなかった Ctrl+Z で自動的に呼ばれる。
    public func suspend() {
        terminal.deactivate()
        stopProcess()
        // 自分で送った SIGTSTP と、再開の SIGCONT をループで二重に処理しない。
        _ = SignalWatcher.consumeSuspend()
        _ = SignalWatcher.consumeContinue()
        resumeTerminal()
    }

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
        terminal.copyToClipboard(text, limit: limit)
    }

    /// 端末を初期化し、終了するまでイベントループを回す。
    ///
    /// - Throws: 入出力が端末でなければ `TerminalError.notATerminal`、
    ///   raw モードへ切り替えられなければ `TerminalError.termiosFailed(errno:)`。
    /// - Postcondition: 起動直後に一度、そのときの画面サイズで `.resize` を通知する。
    ///   戻るときは端末を起動前の状態へ戻し、カーソルを表示に戻す。
    /// - Note: `ApplicationOptions.usesKeyboardProtocol` が有効なら、
    ///   イベントループを回す前に kitty keyboard protocol の対応状況を問い合わせる。
    public func run() throws {
        guard terminal.isTerminal else { throw TerminalError.notATerminal }

        try terminal.enableRawMode()
        defer { terminal.restore() }

        SignalWatcher.install()
        reader.wakeupDescriptor = SignalWatcher.wakeupDescriptor

        if options.usesKeyboardProtocol, supportsKeyboardProtocol() {
            terminal.setKeyboardProtocolEnabled(true)
        }

        if options.usesAlternateScreen { terminal.enterAlternateScreen() }
        terminal.setMouseTrackingEnabled(options.tracksMouse)
        terminal.setBracketedPasteEnabled(options.usesBracketedPaste)
        terminal.setFocusReportingEnabled(options.reportsFocus)
        terminal.setCursorVisible(false)

        buffer.resize(to: terminal.size())
        renderer.invalidate()

        reportedSize = buffer.size
        _ = root.handle(.resize(buffer.size))

        isRunning = true
        lastFrameTime = monotonicSeconds()

        while isRunning {
            // SIGWINCH の処理だけに任せると、シグナルを取りこぼしたときサイズが追従しなくなる。
            if !synchronizeSize() {
                isRunning = false
                break
            }
            draw()

            let events = reader.wait(timeout: options.frameInterval)

            if SignalWatcher.consumeTermination() {
                isRunning = false
                break
            }

            if SignalWatcher.consumeSuspend() {
                suspend()
                if !isRunning { break }
            }

            // 捕まえられない SIGSTOP で止められた後は、端末の設定だけが失われている。
            if SignalWatcher.consumeContinue() {
                resumeTerminal()
                if !isRunning { break }
            }

            if SignalWatcher.consumeWindowResize(), !synchronizeSize() {
                isRunning = false
                break
            }

            for event in events {
                if deliver(event) { continue }
                isRunning = false
                break
            }

            let now = monotonicSeconds()
            root.update(elapsed: now - lastFrameTime)
            lastFrameTime = now
        }

        terminal.setCursorVisible(true)
    }

    /// 端末が kitty keyboard protocol に対応しているかを問い合わせる。
    ///
    /// - Returns: 対応していれば `true`。
    /// - Precondition: raw モードであること。canonical モードでは、応答が行単位でしか届かない。
    private func supportsKeyboardProtocol() -> Bool {
        terminal.write(ANSI.queryKeyboardProtocol)
        terminal.write(ANSI.queryDeviceAttributes)
        terminal.flush()

        let replies = reader.waitForQueryReplies(timeout: queryTimeout)
        return replies.contains { reply in
            if case .keyboardProtocol = reply { return true }
            return false
        }
    }

    /// イベントをルートへ渡す。
    ///
    /// - Parameters:
    ///   - event: ルートへ渡すイベント。
    /// - Returns: ループを続けるなら `true`。
    private func deliver(_ event: InputEvent) -> Bool {
        switch root.handle(event) {
        case .quit:
            return false
        case .handled:
            return true
        case .ignored:
            if options.suspends(onUnhandled: event) {
                suspend()
                return isRunning
            }
            // ルートが処理しなかった Ctrl+C は最後の脱出口として扱う。
            return !options.quits(onUnhandled: event)
        }
    }

    /// 一時停止から戻り、端末と画面を元の状態へ戻す。
    ///
    /// - Postcondition: 画面全体を描き直し、改めて `.resize` を通知する。
    ///   止まっていた時間は `update(elapsed:)` の経過時間に含めない。
    ///   端末を取り戻せなければループを終える。
    private func resumeTerminal() {
        do {
            try terminal.reactivate()
        } catch {
            // 端末を取り戻せないまま続けると、壊れた画面へ描き続けることになる。
            isRunning = false
            return
        }

        terminal.setCursorVisible(false)
        renderer.invalidate()
        // 止まっている間のサイズ変更では SIGWINCH が届かない。次のループで取り直す。
        reportedSize = .zero
        lastFrameTime = monotonicSeconds()
    }

    /// 端末サイズの変化を検出し、バッファを作り直して `.resize` を通知する。
    ///
    /// - Returns: ループを続けるなら `true`。
    /// - Postcondition: 同じサイズについて `.resize` が二重に通知されることはない。
    private func synchronizeSize() -> Bool {
        let size = terminal.size()
        guard size != reportedSize else { return true }

        reportedSize = size
        if size != buffer.size {
            buffer.resize(to: size)
            renderer.invalidate()
        }
        return root.handle(.resize(size)) != .quit
    }

    /// 1 フレーム分を描画する。
    ///
    /// - Precondition: `synchronizeSize()` によってバッファが端末サイズに追従している。
    private func draw() {
        buffer.clear()

        let view = root.body
        let bounds = buffer.bounds
        view.render(into: &buffer, rect: bounds)
        renderer.render(buffer, cursor: root.cursorPosition)
    }
}

/// 起動時の問い合わせに応答を待つ時間（秒）。
private let queryTimeout = 0.25
