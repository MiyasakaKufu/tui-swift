import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 端末を初期化し、入力・描画のループを回すアプリケーション。
@MainActor
public final class Application<Root: Component> {

    private let root: Root
    private let options: ApplicationOptions
    private let terminal: Terminal
    private let reader: InputReader
    private let renderer: Renderer
    private let eventQueue: LoopEventQueue<Root.Message>
    private let graph = ViewGraph()

    /// 別スレッドや `Task` から、`Component.Message` の値をイベントループへ届ける送り口。
    ///
    /// - Note: `Application` 自体は `Sendable` ではないので、別スレッドへはこれを渡す。
    /// - Note: `TerminalApp` のアプリからは届かない。
    nonisolated public let sender: MessageSender<Root.Message>

    private var buffer: Buffer
    /// 最後に `.resize` として通知したサイズ。
    private var reportedSize = Size.zero
    /// 最後にフレームを数えた時刻。
    private var lastFrameTime = 0.0
    private var isRunning = false
    private var hasRun = false

    /// 端末を戻した後にプロセスを止める処理。
    ///
    /// - Note: 実際に止めるとテストプロセスまで止まるため、テストでは差し替える。
    var stopProcess: () -> Void = { SignalWatcher.stopProcess() }

    /// ルートと設定を指定してアプリケーションを作る。
    ///
    /// - Parameters:
    ///   - root: 画面を組み立て、イベントを受け取るルート。
    ///   - options: 起動時の設定。
    ///   - terminal: 使用する `Terminal`。省略すると標準入出力の記述子で作る。テストでは差し替える。
    public init(
        root: Root,
        options: ApplicationOptions = .default,
        terminal: Terminal? = nil
    ) {
        // 既定値に `Terminal()` と書き直すとコンパイルが通らない。
        // 既定引数の式はこの宣言の隔離を継承せず、非隔離の文脈からの呼び出しになる。
        let terminal = terminal ?? Terminal()
        self.root = root
        self.options = options
        self.buffer = Buffer(size: .zero, ambiguousWidth: options.ambiguousWidth)
        self.terminal = terminal
        self.reader = InputReader(descriptor: terminal.inputDescriptor)
        self.renderer = Renderer(output: terminal)
        let eventQueue = LoopEventQueue<Root.Message>()
        self.eventQueue = eventQueue
        self.sender = MessageSender(eventQueue: eventQueue)
    }

    /// ループを終了させる。イベントハンドラの中からも呼べる。
    public func stop() {
        isRunning = false
        // ループを起こさずに済ませてはいけない。`Task` から呼ばれたとき、ループは次の
        // `LoopEvent` を待ったまま `isRunning` を読み直さず、キーが届くまで終わらない。
        eventQueue.post(.wake)
    }

    /// ウィンドウタイトルとアイコン名を設定する。
    ///
    /// - Parameters:
    ///   - title: 設定するタイトル。
    /// - Note: 起動時のタイトルは `ApplicationOptions.windowTitle` で指定する。
    ///   終了時と一時停止時には、いずれも設定する前のタイトルへ戻る。
    public func setWindowTitle(_ title: String) {
        terminal.setWindowTitle(title)
    }

    /// カーソルの形と点滅の有無を切り替える。
    ///
    /// - Parameters:
    ///   - shape: 設定する形。
    /// - Note: 起動時の形は `ApplicationOptions.cursorShape` で指定する。
    ///   終了時と一時停止時には、いずれも端末の設定どおりの形へ戻る。
    public func setCursorShape(_ shape: CursorShape) {
        terminal.setCursorShape(shape)
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
        // ループを起こさずに済ませてはいけない。`Task` から呼ばれたとき、次の `LoopEvent` が
        // 届くまで描き直されず、再開した後の画面が空のまま残る。
        eventQueue.post(.wake)
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
    /// - Precondition: 1 つの `Application` で呼べるのは 1 回だけ。
    /// - Note: `ApplicationOptions.usesKeyboardProtocol` が有効なら、
    ///   イベントループを回す前に kitty keyboard protocol の対応状況を問い合わせる。
    public func run() async throws {
        precondition(!hasRun, "run() は 1 つの Application で 1 回だけ呼べる")
        hasRun = true
        guard terminal.isTerminal else { throw TerminalError.notATerminal }

        try terminal.enableRawMode()
        defer { terminal.restore() }

        SignalWatcher.install()

        if options.usesKeyboardProtocol, supportsKeyboardProtocol() {
            terminal.setKeyboardProtocolEnabled(true)
        }

        if options.usesAlternateScreen { terminal.enterAlternateScreen() }
        terminal.setMouseTracking(options.mouseTracking)
        terminal.setBracketedPasteEnabled(options.usesBracketedPaste)
        terminal.setFocusReportingEnabled(options.reportsFocus)
        if let title = options.windowTitle { terminal.setWindowTitle(title) }
        if let shape = options.cursorShape { terminal.setCursorShape(shape) }
        terminal.setCursorVisible(false)

        buffer.resize(to: terminal.size())
        renderer.invalidate()

        reportedSize = buffer.size
        _ = root.handle(.resize(buffer.size))

        isRunning = true
        lastFrameTime = monotonicSeconds()

        let inputStopped = startReadingInput()
        draw()

        // `LoopEvent` を 1 つ取り出すたびに描き直してはいけない。ループより速く溜まると、
        // 溜まった数だけ描き直しが走り、後から届いたキーが `handle(_:)` に届くまでの遅れが伸び続ける。
        loop: for await _ in eventQueue.arrivals {
            let events = eventQueue.take()
            if events.isEmpty { continue loop }

            var isIdle = events.allSatisfy { event in
                if case .idle = event { return true }
                return false
            }
            for event in events where isRunning {
                switch event {
                case .inputs(let inputs):
                    for input in inputs {
                        if !deliver(input) { break loop }
                    }
                case .message(let message):
                    if root.receive(message) == .quit { break loop }
                case .wake, .idle:
                    break
                }
            }

            if SignalWatcher.consumeTermination() { break loop }

            if SignalWatcher.consumeSuspend() {
                isIdle = false
                suspend()
                if !isRunning { break loop }
            }

            // 捕まえられない SIGSTOP で止められた後は、端末の設定だけが失われている。
            if SignalWatcher.consumeContinue() {
                isIdle = false
                resumeTerminal()
                if !isRunning { break loop }
            }

            // SIGWINCH の処理だけに任せると、シグナルを取りこぼしたときサイズが追従しなくなる。
            let sizeBeforeSynchronizing = reportedSize
            if !synchronizeSize() { break loop }

            // 何も起きていない `.idle` で先へ進んではいけない。`frameInterval` が `nil` でも
            // `update(elapsed:)` が一定の間隔で呼ばれ、描き直すたびに制御コードが書き出される。
            if isIdle, reportedSize == sizeBeforeSynchronizing { continue loop }

            let now = monotonicSeconds()
            root.update(elapsed: now - lastFrameTime)
            lastFrameTime = now

            if !isRunning { break loop }
            draw()
        }

        isRunning = false

        // `startReadingInput()` が作ったスレッドの終了を待たずに戻ってはいけない。
        // 残ったスレッドが自己パイプを読み捨て続けるので、次にシグナルを使うコードが合図を取りこぼす。
        // `LoopEventQueue` を閉じてから起こす順序も変えてはいけない。
        // 逆にすると閉じる前の `LoopEventQueue` へ入れ、`poll(2)` へ戻って次にバイトが届くまで終わらない。
        eventQueue.close()
        SignalWatcher.wakeUp()
        // `run()` の `Task` の中で直接待ってはいけない。その `Task` が打ち切られていると、
        // `for await` がすぐに抜けて、スレッドの終了を待たずに戻る。
        await Task { for await _ in inputStopped {} }.value

        terminal.setCursorVisible(true)
    }

    /// tty からバイト列を読み、組み立てた `InputEvent` を `LoopEventQueue` へ入れるスレッドを作る。
    ///
    /// - Returns: スレッドが終わったときに終了する `AsyncStream`。
    private func startReadingInput() -> AsyncStream<Void> {
        let (stopped, stoppedContinuation) = AsyncStream<Void>.makeStream()
        let descriptor = terminal.inputDescriptor
        let wakeupDescriptor = SignalWatcher.wakeupDescriptor
        // 自己パイプが無いときに `frameInterval` のまま待ってはいけない。`nil` なら `poll(2)` が
        // 無期限に待ち、終了時に起こせないので `run()` が戻らない。
        let isFallingBack = wakeupDescriptor == nil && options.frameInterval == nil
        let timeout = isFallingBack ? wakeupFallbackInterval : options.frameInterval
        let emptyEvent: LoopEvent<Root.Message> = isFallingBack ? .idle : .wake
        let eventQueue = self.eventQueue

        // まだ返していない分を引き渡さないと、`supportsKeyboardProtocol()` の待ちの間に
        // 届いたキーが落ちる。待ちの間に読んだ分は、待った側の `InputReader` が抱えている。
        let unread = reader.takeUnreadState()

        // `poll(2)` をアクタの上で呼んではいけない。キーが届くまでループが進まず、
        // `MessageSender` で送られた値が処理されない。
        // `InputReader` を外で作って渡すと、非 Sendable の参照がスレッドを跨ぐ。
        Thread.detachNewThread {
            let reader = InputReader(descriptor: descriptor)
            reader.wakeupDescriptor = wakeupDescriptor
            reader.adopt(unread)

            while true {
                let events = reader.wait(timeout: timeout)

                let event: LoopEvent<Root.Message> = events.isEmpty ? emptyEvent : .inputs(events)
                if !eventQueue.post(event) { break }
            }

            stoppedContinuation.finish()
        }

        return stopped
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
        graph.renderFrame(view, into: &buffer, ambiguousWidth: options.ambiguousWidth)
        renderer.render(buffer, cursor: root.cursorPosition)
    }
}

/// 自己パイプが無く、`frameInterval` も無いときに、`poll(2)` の待ちを切り上げる間隔（秒）。
///
/// 起こす手段が無いので、この間隔でループへ戻り、終了とシグナルを確かめる。
private let wakeupFallbackInterval = 0.1

/// 起動時の問い合わせに応答を待つ時間（秒）。
private let queryTimeout = 0.25

extension Application where Root: TerminalApp {
    /// ルートを作り、アプリケーションを起動する。
    ///
    /// - Throws: `run()` が投げるもの。
    static func start() async throws {
        try await Application(root: Root(), options: Root.options).run()
    }
}
