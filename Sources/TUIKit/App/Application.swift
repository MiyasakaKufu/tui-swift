#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 端末を初期化し、入力・描画のループを回すアプリケーション。
public final class Application {

    /// 起動時の設定。
    public struct Options {
        /// 代替画面バッファへ切り替える（終了時に元の画面が戻る）。
        public var usesAlternateScreen: Bool
        /// マウスイベントを受け取る。
        public var tracksMouse: Bool
        /// ブラケットペーストを有効にする。
        public var usesBracketedPaste: Bool
        /// 入力がなくても一定間隔で再描画する（秒）。`nil` なら入力があるまで待つ。
        public var frameInterval: Double?

        public init(
            usesAlternateScreen: Bool = true,
            tracksMouse: Bool = false,
            usesBracketedPaste: Bool = true,
            frameInterval: Double? = nil
        ) {
            self.usesAlternateScreen = usesAlternateScreen
            self.tracksMouse = tracksMouse
            self.usesBracketedPaste = usesBracketedPaste
            self.frameInterval = frameInterval
        }

        public static let `default` = Options()
    }

    private let root: any Component
    private let options: Options
    private let terminal: Terminal
    private let reader: InputReader
    private let renderer: Renderer

    private var buffer = Buffer(size: .zero)
    private var isRunning = false

    public init(
        root: any Component,
        options: Options = .default,
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
        if options.usesAlternateScreen { terminal.enterAlternateScreen() }
        terminal.setMouseTrackingEnabled(options.tracksMouse)
        terminal.setBracketedPasteEnabled(options.usesBracketedPaste)
        terminal.setCursorVisible(false)

        buffer.resize(to: terminal.size())
        renderer.invalidate()

        // 起動直後の画面サイズもリサイズイベントとして通知する。
        _ = root.handle(.resize(buffer.size))

        isRunning = true
        var lastFrame = monotonicSeconds()

        while isRunning {
            draw()

            let events = reader.wait(timeout: options.frameInterval)

            if SignalWatcher.consumeTermination() {
                isRunning = false
                break
            }

            if SignalWatcher.consumeWindowResize() {
                let newSize = terminal.size()
                if newSize != buffer.size {
                    buffer.resize(to: newSize)
                    renderer.invalidate()
                    if root.handle(.resize(newSize)) == .quit {
                        isRunning = false
                        break
                    }
                }
            }

            for event in events {
                if root.handle(event) == .quit {
                    isRunning = false
                    break
                }
            }

            let now = monotonicSeconds()
            root.update(elapsed: now - lastFrame)
            lastFrame = now
        }

        // 画面をきれいにしてから戻す。
        terminal.setCursorVisible(true)
    }

    /// 1 フレーム分を描画する。
    private func draw() {
        let size = terminal.size()
        if size != buffer.size {
            buffer.resize(to: size)
            renderer.invalidate()
        }
        buffer.clear()

        let view = root.body()
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
