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
    private var isRunning = false

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

    /// 端末を初期化し、終了するまでイベントループを回す。
    public func run() throws {
        guard terminal.isTerminal else { throw TerminalError.notATerminal }

        try terminal.enableRawMode()
        defer { terminal.restore() }

        SignalWatcher.install()
        reader.wakeupDescriptor = SignalWatcher.wakeupDescriptor

        if options.usesAlternateScreen { terminal.enterAlternateScreen() }
        terminal.setMouseTrackingEnabled(options.tracksMouse)
        terminal.setBracketedPasteEnabled(options.usesBracketedPaste)
        terminal.setCursorVisible(false)

        buffer.resize(to: terminal.size())
        renderer.invalidate()

        // 起動直後の画面サイズもリサイズイベントとして通知する。
        reportedSize = buffer.size
        _ = root.handle(.resize(buffer.size))

        isRunning = true
        var lastFrame = monotonicSeconds()

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
            root.update(elapsed: now - lastFrame)
            lastFrame = now
        }

        // 画面をきれいにしてから戻す。
        terminal.setCursorVisible(true)
    }

    /// イベントをルートへ渡す。ループを続けるなら `true` を返す。
    private func deliver(_ event: InputEvent) -> Bool {
        switch root.handle(event) {
        case .quit:
            return false
        case .handled:
            return true
        case .ignored:
            // ルートが処理しなかった Ctrl+C は最後の脱出口として扱う。
            return !options.quits(onUnhandled: event)
        }
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

/// 起動からの経過を表す単調増加の秒数。
private func monotonicSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_MONOTONIC, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}
