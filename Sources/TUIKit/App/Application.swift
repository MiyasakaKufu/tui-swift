import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 端末デバイスを raw モードにし、``InputReader`` が端末デバイスから受け取ったバイト列を ``InputEvent`` にすることと ``Buffer`` を端末デバイスへ書き出すことを繰り返す型。
@MainActor
public final class Application<Root: TerminalApp> {

    private let root: Root
    private let options: ApplicationOptions
    private let terminal: Terminal
    private let reader: InputReader
    private let renderer: Renderer
    private let eventQueue: LoopEventQueue
    private let context = ApplicationContext()
    /// `Application.draw()` で読んだ状態が変わったら、`Application.eventQueue` へ知らせる `RedrawTrigger`。
    private let redrawTrigger: RedrawTrigger
    /// ``TerminalApp`` に準拠する型の ``State``・``FocusState`` の記憶域を持つ `ViewNode`。
    private let rootNode: ViewNode

    private var buffer: Buffer
    /// 最後に `.resize` として通知したサイズ。
    private var reportedSize = Size.zero
    private var isRunning = false
    private var hasRun = false
    /// `Application.draw()` を呼び出した回数。
    private var drawCount = 0

    /// 端末デバイスの termios と、端末エミュレータへ送ったモードを戻した後に、プロセスを止めるクロージャ。
    ///
    /// - Note: 実際に止めるとテストプロセスまで止まるため、テストでは差し替える。
    var stopProcess: () -> Void = { SignalWatcher.stopProcess() }

    /// ``TerminalApp`` に準拠する型のインスタンスと ``ApplicationOptions`` を指定して ``Application`` を作る。
    ///
    /// - Parameters:
    ///   - root: 画面を組み立て、イベントを受け取る、``TerminalApp`` に準拠する型のインスタンス。
    ///   - options: 起動時の設定。
    ///   - terminal: 使用する `Terminal`。省略すると標準入出力の記述子で作る。テストでは差し替える。
    /// - Precondition: `Root` はクラスではない。
    /// - Postcondition: `root` の ``State``・``FocusState`` を付けたプロパティは、この ``Application`` が持つ記憶域に結び付いている。
    public init(
        root: Root,
        options: ApplicationOptions = .default,
        terminal: Terminal = Terminal()
    ) {
        self.root = root
        self.options = options
        self.buffer = Buffer(size: .zero, ambiguousWidth: options.ambiguousWidth)
        self.terminal = terminal
        self.reader = InputReader(descriptor: terminal.inputDescriptor)
        self.renderer = Renderer(output: terminal)
        // クラスで準拠した型を受け付けてはいけない。普通の `var` に置いた状態を変えても描き直されず、何の警告も出ない。
        precondition(!(Root.self is AnyObject.Type), "TerminalApp には構造体か列挙型で準拠する。状態は @State を付けたプロパティに置く")
        let eventQueue = LoopEventQueue()
        self.eventQueue = eventQueue
        self.redrawTrigger = RedrawTrigger(eventQueue: eventQueue)
        self.rootNode = context.graph.makeDetachedNode()
        context.graph.bindState(of: root, to: rootNode)
        context.focus.stopsDelivering = { root.isFinished }
        // `.motion` 以外でも有効にしたくなるが、`.buttons` ではボタンを離した後の移動が届かないので、押した位置の `View` に `true` を渡したまま、次にボタンを押すかホイールを回すまで `false` を渡せない。
        context.hover.isEnabled = options.mouseTracking == .motion
    }

    /// ループを終了させる。イベントハンドラの中からも呼び出せる。
    public func stop() {
        isRunning = false
        // ループを起こさずに済ませてはいけない。`Task` から呼び出されたとき、ループは次の `LoopEvent` を待ったまま `isRunning` を読み直さず、キーが届くまで終わらない。
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
    ///   終了時と一時停止時には、いずれも端末エミュレータの設定どおりの形へ戻る。
    public func setCursorShape(_ shape: CursorShape) {
        terminal.setCursorShape(shape)
    }

    /// 端末デバイスの termios と、端末エミュレータへ送ったモードを元に戻してプロセスを止め、再開したら設定し直す。
    ///
    /// raw モードでは `ISIG` を無効にしているため、Ctrl+Z はシグナルにならずキーとして届く。
    /// 一時停止したい ``TerminalApp`` に準拠する型は、そのキーを受け取ったときにこのメソッドを呼び出す。
    ///
    /// - Postcondition: 再開したら画面全体を描き直し、改めて `.resize` を通知する。
    /// - Note: `ApplicationOptions.suspendsOnControlZ` が有効なら、``TerminalApp/handle(_:)`` が `.ignored` を返した Ctrl+Z で自動的に呼び出される。
    public func suspend() {
        terminal.deactivate()
        stopProcess()
        // 自分で送った SIGTSTP と、再開の SIGCONT をループで二重に処理しない。
        _ = SignalWatcher.consumeSuspend()
        _ = SignalWatcher.consumeContinue()
        resumeTerminal()
        // ループを起こさずに済ませてはいけない。`Task` から呼び出されたとき、次の `LoopEvent` が届くまで描き直されず、再開した後の画面が空のまま残る。
        eventQueue.post(.wake)
    }

    /// 文字列をクリップボードへ渡す。
    ///
    /// - Parameters:
    ///   - text: クリップボードへ渡す文字列。空文字列を渡すとクリップボードを空にする。
    ///   - limit: Base64 に変換した後の長さの上限（バイト）。
    /// - Returns: 端末エミュレータへ送ったなら `true`。上限を超えて送らなかったなら `false`。
    /// - Note: 端末エミュレータが OSC 52 を拒否していれば、送ってもクリップボードは変わらない。
    ///   応答がないため、戻り値では区別できない。
    @discardableResult
    public func copyToClipboard(_ text: String, limit: Int = ANSI.clipboardLimit) -> Bool {
        terminal.copyToClipboard(text, limit: limit)
    }

    /// 端末デバイスを raw モードにし、端末エミュレータへ送るモードを切り替えて、終了するまでイベントループを回す。
    ///
    /// - Throws: 入出力が端末デバイスでなければ ``TerminalError/notATerminal``、raw モードへ切り替えられなければ `TerminalError.termiosFailed(errno:)`。
    /// - Postcondition: 起動直後に一度、そのときの端末デバイスのウィンドウサイズで `.resize` を通知する。
    ///   戻るときは端末デバイスの termios と、端末エミュレータへ送ったモードを起動前へ戻し、カーソルを表示に戻す。
    /// - Postcondition: 戻るときは、``View/task(_:)`` で始めた `Task` をすべて打ち切っている。その `Task` が終わるのは待たない。
    /// - Precondition: 1 つの ``Application`` で呼び出せるのは 1 回だけ。
    /// - Note: `ApplicationOptions.usesKeyboardProtocol` が有効なら、
    ///   イベントループを回す前に kitty keyboard protocol の対応状況を問い合わせる。
    public func run() async throws {
        precondition(!hasRun, "run() は 1 つの Application で 1 回だけ呼び出せる")
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

        let inputStopped = startReadingInput()
        if root.isFinished {
            eventQueue.post(.wake)
        } else {
            draw()
        }

        // `LoopEvent` を 1 つ取り出すたびに描き直してはいけない。ループより速く溜まると、
        // 溜まった数だけ描き直しが走り、後から届いたキーが `handle(_:)` に届くまでの遅れが伸び続ける。
        loop: for await _ in eventQueue.arrivals {
            // 先頭で `TerminalApp.isFinished` を読むのをやめてはいけない。最初の `.resize` で `true` になったときも周回の後半へ進み、ウィンドウサイズが変わっていれば、終了を宣言した後の `TerminalApp.handle(_:)` へ `.resize` を渡す。
            if root.isFinished { break loop }

            let events = eventQueue.take()
            if events.isEmpty { continue loop }

            var isIdle = events.allSatisfy { event in
                switch event {
                case .idle:
                    return true
                case .invalidated(let generation):
                    return generation < drawCount
                case .inputs, .wake:
                    return false
                }
            }
            for event in events where isRunning {
                switch event {
                case .inputs(let inputs):
                    for input in inputs {
                        if !deliver(input) { break loop }
                    }
                case .invalidated, .wake, .idle:
                    break
                }
            }

            if SignalWatcher.consumeTermination() { break loop }

            if SignalWatcher.consumeSuspend() {
                isIdle = false
                suspend()
                if !isRunning { break loop }
            }

            // SIGCONT の確認を消したり、`SignalWatcher.consumeSuspend()` の分岐の中へまとめたりしてはいけない。
            // 捕まえられない SIGSTOP で止められたときは SIGTSTP のハンドラが動かず、`SignalWatcher.consumeSuspend()` が `true` にならない。再開しても `Application.resumeTerminal()` が呼び出されず、端末デバイスの termios と、端末エミュレータへ送ったモードを設定し直さないまま描き続ける。
            if SignalWatcher.consumeContinue() {
                isIdle = false
                resumeTerminal()
                if !isRunning { break loop }
            }

            // SIGWINCH の処理だけに任せると、シグナルを取りこぼしたときサイズが追従しなくなる。
            let sizeBeforeSynchronizing = reportedSize
            if !synchronizeSize() { break loop }

            // 何も起きていない `.idle` で先へ進んではいけない。自己パイプが無いときに一定の間隔で描き直すことになり、描き直すたびに `ANSI.beginSynchronizedUpdate` などが端末デバイスへ書き出される。
            if isIdle, reportedSize == sizeBeforeSynchronizing { continue loop }

            if !isRunning || root.isFinished { break loop }
            draw()
        }

        isRunning = false
        // `View.task(_:)` の `Task` が終わるのを待ってはいけない。打ち切りに応じない処理があると、TUIKit アプリが `TerminalApp.isFinished` で終了を宣言しても `Application.run()` が戻らない。
        context.graph.removeAllNodes()

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

    /// 端末デバイスからバイト列を読み、組み立てた ``InputEvent`` を `LoopEventQueue` へ入れるスレッドを作る。
    ///
    /// - Returns: スレッドが終わったときに終了する `AsyncStream`。
    private func startReadingInput() -> AsyncStream<Void> {
        let (stopped, stoppedContinuation) = AsyncStream<Void>.makeStream()
        let descriptor = terminal.inputDescriptor
        let wakeupDescriptor = SignalWatcher.wakeupDescriptor
        // 自己パイプが無いときに無期限に待ってはいけない。終了時に `poll(2)` を起こせないので `run()` が戻らない。
        let isFallingBack = wakeupDescriptor == nil
        let timeout: Double? = isFallingBack ? wakeupFallbackInterval : nil
        let emptyEvent: LoopEvent = isFallingBack ? .idle : .wake
        let eventQueue = self.eventQueue

        // まだ返していない分を引き渡さないと、`Application.supportsKeyboardProtocol()` の待ちの間に届いたキーが落ちる。待ちの間に読んだ分は、`Application.supportsKeyboardProtocol()` が使った `Application.reader` が抱えている。
        let unread = reader.takeUnreadState()

        // `poll(2)` をアクタの上で呼び出してはいけない。キーが届くまでループが進まず、`View.task(_:)` の `Task` で変えた状態が描き直されない。
        // `InputReader` を外で作って渡すと、非 Sendable の参照がスレッドを跨ぐ。
        Thread.detachNewThread {
            let reader = InputReader(descriptor: descriptor)
            reader.wakeupDescriptor = wakeupDescriptor
            reader.adopt(unread)

            while true {
                let events = reader.wait(timeout: timeout)

                let event: LoopEvent = events.isEmpty ? emptyEvent : .inputs(events)
                if !eventQueue.post(event) { break }
            }

            stoppedContinuation.finish()
        }

        return stopped
    }

    /// 端末エミュレータが kitty keyboard protocol に対応しているかを問い合わせる。
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

    /// ``InputEvent`` を ``View`` へ渡し、どの ``View`` も処理しなければ ``TerminalApp/handle(_:)`` へ渡す。
    ///
    /// - Parameters:
    ///   - event: 渡す ``InputEvent``。
    /// - Returns: ループを続けるなら `true`。``View`` か ``TerminalApp/handle(_:)`` へ渡した後に ``TerminalApp/isFinished`` が `true` なら `false`。
    private func deliver(_ event: InputEvent) -> Bool {
        let isHandledByView: Bool
        switch event {
        case .key(let keyEvent):
            isHandledByView = context.deliver(keyEvent) == .handled
        case .mouse(let mouseEvent):
            isHandledByView = context.deliver(mouseEvent)
        case .paste:
            isHandledByView = context.deliverPaste(event)
        case .resize, .focus:
            isHandledByView = false
        }
        if root.isFinished { return false }
        if isHandledByView { return true }

        let result = root.handle(event)
        if root.isFinished { return false }

        switch result {
        case .handled:
            return true
        case .ignored:
            if options.suspends(onUnhandled: event) {
                suspend()
                return isRunning
            }
            // `ApplicationOptions.quits(onUnhandled:)` を見ずにループを続けてはいけない。raw モードでは `ISIG` を切っているので、Ctrl+C は SIGINT にならずこの `InputEvent` として届く。`TerminalApp.handle(_:)` が Ctrl+C を扱わない TUIKit アプリを、`ApplicationOptions.quitsOnControlC` が `true` でも Ctrl+C で止められなくなる。
            return !options.quits(onUnhandled: event)
        }
    }

    /// 一時停止から戻り、端末デバイスの termios と、端末エミュレータへ送ったモードを設定し直す。
    ///
    /// - Postcondition: 画面全体を描き直し、改めて `.resize` を通知する。
    ///   ``Terminal/reactivate()`` がエラーを投げたらループを終える。
    private func resumeTerminal() {
        do {
            try terminal.reactivate()
        } catch {
            // `Terminal.reactivate()` が失敗したまま続けると、壊れた画面へ描き続けることになる。
            isRunning = false
            return
        }

        terminal.setCursorVisible(false)
        renderer.invalidate()
        // 止まっている間のサイズ変更では SIGWINCH が届かない。次のループで取り直す。
        reportedSize = .zero
    }

    /// 端末デバイスのウィンドウサイズの変化を検出し、``Buffer`` を作り直して `.resize` を通知する。
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
        _ = root.handle(.resize(size))
        return !root.isFinished
    }

    /// ``TerminalApp/body`` を ``Buffer`` に書き込み、``Renderer`` で端末デバイスへ書き出す。
    ///
    /// - Precondition: `Application.synchronizeSize()` によって ``Buffer`` が端末デバイスのウィンドウサイズに追従している。
    /// - Postcondition: たどった後にフォーカスが変わったら、もう 1 回描く。そのもう 1 回では、さらには描かない。
    /// - Postcondition: 端末エミュレータのカーソルは、``TerminalApp/cursorPosition`` が `nil` 以外ならその位置に、`nil` ならフォーカスを持つ ``TextField`` が示す位置に置く。どちらも無ければ隠す。
    /// - Postcondition: 描くときに読んだ状態と ``TerminalApp/isFinished`` が後で変わったら、`Application.eventQueue` へ `.invalidated` が入る。
    /// - Postcondition: ``View/onChange(of:_:)`` が値の変化を見つけたら、描き終えた後にクロージャを呼び出している。
    private func draw() {
        drawCount += 1
        let changeActions = redrawTrigger.track(generation: drawCount) {
            // `TerminalApp.isFinished` を読むのをやめてはいけない。`View.task(_:)` のクロージャで `true` にしても、それを `TerminalApp.body` が読んでいなければループが起きず、次に `InputEvent` が届くまで終わらない。
            _ = root.isFinished
            return context.draw({ root.body }, into: &buffer, ambiguousWidth: options.ambiguousWidth) { buffer in
                renderer.render(buffer, cursor: root.cursorPosition ?? context.cursorPosition)
            }
        }
        // `RedrawTrigger.track(generation:_:)` のクロージャの中で呼び出してはいけない。その中での代入はループに知らせないので、クロージャが変えた状態が、次に `InputEvent` が届くまで画面に出ない。
        for action in changeActions { action() }
    }
}

/// 自己パイプが無いときに、`poll(2)` の待ちを切り上げる間隔（秒）。
///
/// 起こす手段が無いので、この間隔でループへ戻り、終了とシグナルを確かめる。
private let wakeupFallbackInterval = 0.1

/// 起動時の問い合わせに応答を待つ時間（秒）。
private let queryTimeout = 0.25
