#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import XCTest
import CTUITestSupport
@testable import TUIKit

/// 疑似端末（pty）の上で `Application` を実際に動かして確かめるテスト。
@MainActor
final class ApplicationBugReproductionTests: XCTestCase {

    /// `TerminalApp.handle(_:)` の実行中に端末デバイスのウィンドウサイズが変わっても `.resize` が届く。
    func testResizeDuringEventHandlingIsReported() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        let initialSize = Size(width: 77, height: 23)
        let resizedSize = Size(width: 100, height: 30)
        XCTAssertEqual(setTerminalSize(master, initialSize), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み捨て続ける。
        let drain = OutputDrain(descriptor: master)
        drain.start()
        defer { drain.stop() }

        let app = ResizeRecordingApp()
        let application = Application(
            root: app,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        app.onFirstKey = {
            _ = setTerminalSize(master, resizedSize)
            raise(SIGWINCH)
        }
        app.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let hasStartedLoop = app.hasStartedLoop
        let sender = Thread {
            guard hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, UInt8(ascii: "a"))
            Thread.sleep(forTimeInterval: 0.2)
            writeByte(master, UInt8(ascii: "b"))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(app.reportedSizes, [initialSize, resizedSize])
    }

    /// `ApplicationOptions.reportsFocus` を有効にすると `.focus` が届き、終了時に通知が止まる。
    func testApplicationEnablesFocusReporting() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let app = FocusRecordingApp()
        let application = Application(
            root: app,
            options: ApplicationOptions(
                usesAlternateScreen: false,
                reportsFocus: true,
                frameInterval: 1.0 / 60
            ),
            terminal: Terminal(input: slave, output: slave)
        )
        app.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let hasStartedLoop = app.hasStartedLoop
        let sender = Thread {
            guard hasStartedLoop.wait(timeout: 5) else { return }
            writeBytes(master, Array("\u{1B}[I".utf8))
            Thread.sleep(forTimeInterval: 0.2)
            writeBytes(master, Array("\u{1B}[O".utf8))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(app.focusChanges, [true, false])
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableFocusReporting, timeout: 2),
            "`ANSI.enableFocusReporting` が書き出されていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableFocusReporting, timeout: 2),
            "終了時にフォーカス通知が止められていない"
        )
    }

    /// `ApplicationOptions.ambiguousWidth` が `.narrow` なら `BorderStyle.rounded` のまま、`.wide` なら `BorderStyle.ascii` で枠線が描かれる。
    func testApplicationDrawsBorderWithTheAmbiguousWidthOption() async throws {
        // 枠全体（`╭──╮`）を探してはいけない。`Application` が最初にメソッドを呼び出す `View` は `Buffer` 全体に広がるので、角と角の間は `Buffer` の幅いっぱいまで続き、その並びは出力に現れない。
        let cases: [(DisplayWidth.AmbiguousWidth, [String])] = [
            (.narrow, ["╭──", "│ab"]),
            (.wide, ["+--", "|ab"]),
        ]
        for (ambiguous, fragments) in cases {
            var masterDescriptor: Int32 = -1
            var slaveDescriptor: Int32 = -1
            let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
            try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
            let master = masterDescriptor
            let slave = slaveDescriptor
            defer {
                close(slave)
                close(master)
            }

            XCTAssertEqual(setTerminalSize(master, Size(width: 20, height: 5)), 0)

            // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み続ける。
            let drain = OutputDrain(descriptor: master, recordsOutput: true)
            drain.start()
            defer { drain.stop() }

            let app = BorderDrawingApp()
            let application = Application(
                root: app,
                options: ApplicationOptions(
                    usesAlternateScreen: false,
                    usesKeyboardProtocol: false,
                    frameInterval: 1.0 / 60,
                    ambiguousWidth: ambiguous
                ),
                terminal: Terminal(input: slave, output: slave)
            )
            app.onFramesDrawn = { [weak application] in application?.stop() }

            try await application.run()

            for fragment in fragments {
                XCTAssertTrue(
                    drain.waitForOutput(containing: fragment, timeout: 2),
                    "\(ambiguous) のとき \(fragment) が描かれていない"
                )
            }
        }
    }

    /// `ApplicationOptions.mouseTracking` が `.motion` なら、ボタンを押していない移動が `.move` として届く。
    func testApplicationEnablesMouseMotionTracking() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let app = MouseRecordingApp()
        let application = Application(
            root: app,
            options: ApplicationOptions(
                usesAlternateScreen: false,
                mouseTracking: .motion,
                frameInterval: 1.0 / 60
            ),
            terminal: Terminal(input: slave, output: slave)
        )
        app.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let hasStartedLoop = app.hasStartedLoop
        let sender = Thread {
            guard hasStartedLoop.wait(timeout: 5) else { return }
            writeBytes(master, Array("\u{1B}[<35;4;2M".utf8))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(
            app.mouseEvents,
            [MouseEvent(position: Point(x: 3, y: 1), button: .none, action: .move)]
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableMouseMotionTracking, timeout: 2),
            "`ANSI.enableMouseMotionTracking` が書き出されていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableMouseTracking, timeout: 2),
            "終了時にマウスの通知が止められていない"
        )
    }

    /// `View.onHover(perform:)` のクロージャは、`ApplicationOptions.mouseTracking` が `.motion` のときだけ呼び出される。
    func testHoverFollowsPointerOnlyWithMotionTracking() async throws {
        for tracking in [MouseTracking.motion, .buttons] {
            var masterDescriptor: Int32 = -1
            var slaveDescriptor: Int32 = -1
            let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
            try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
            let master = masterDescriptor
            let slave = slaveDescriptor
            defer {
                close(slave)
                close(master)
            }

            XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

            // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み捨て続ける。
            let drain = OutputDrain(descriptor: master)
            drain.start()
            defer { drain.stop() }

            let app = HoverRecordingApp()
            let application = Application(
                root: app,
                options: ApplicationOptions(
                    usesAlternateScreen: false,
                    mouseTracking: tracking,
                    frameInterval: 1.0 / 60
                ),
                terminal: Terminal(input: slave, output: slave)
            )
            app.onTimeout = { [weak application] in application?.stop() }

            // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
            let hasStartedLoop = app.hasStartedLoop
            let sender = Thread {
                guard hasStartedLoop.wait(timeout: 5) else { return }
                writeBytes(master, Array("\u{1B}[<0;1;1M\u{1B}[<0;1;1m".utf8))
            }
            sender.start()

            try await application.run()

            XCTAssertEqual(app.releaseCount, 1, "\(tracking) のときにボタンを離したことが届いていない")
            XCTAssertEqual(app.hovers, tracking == .motion ? [true] : [], "\(tracking) のとき")
        }
    }

    /// 対応する端末エミュレータでは kitty keyboard protocol を有効にし、Ctrl+I と Tab を区別する。
    func testApplicationEnablesKeyboardProtocolWhenSupported() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let app = KeyRecordingApp(expectedCount: 2)
        let application = Application(
            root: app,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        app.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、問い合わせが届いてから応答する。
        let responder = Thread {
            guard drain.waitForOutput(containing: ANSI.queryKeyboardProtocol, timeout: 5) else { return }
            writeBytes(master, Array("\u{1B}[?1u\u{1B}[?62;c".utf8))
            guard drain.waitForOutput(containing: ANSI.enableKeyboardProtocol, timeout: 5) else { return }

            writeBytes(master, Array("\u{1B}[105;5u".utf8))
            Thread.sleep(forTimeInterval: 0.2)
            writeBytes(master, [0x09])
        }
        responder.start()

        try await application.run()

        XCTAssertEqual(
            app.keys,
            [KeyEvent(.character("i"), modifiers: .control), KeyEvent(.tab)],
            "Ctrl+I と Tab が区別されていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableKeyboardProtocol, timeout: 2),
            "対応している端末エミュレータのとき `ANSI.enableKeyboardProtocol` が書き出されていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableKeyboardProtocol, timeout: 2),
            "終了時に元の形式へ戻していない"
        )
    }

    /// 応答しない端末エミュレータでは kitty keyboard protocol を有効にしない。
    func testApplicationLeavesKeyboardProtocolOffWhenUnsupported() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let app = KeyRecordingApp(expectedCount: 1)
        let application = Application(
            root: app,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        app.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let hasStartedLoop = app.hasStartedLoop
        let sender = Thread {
            guard hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, 0x09)
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(app.keys, [KeyEvent(.tab)], "従来どおりの形式で届いていない")
        XCTAssertFalse(
            drain.waitForOutput(containing: ANSI.enableKeyboardProtocol, timeout: 0.5),
            "応答しない端末エミュレータで有効にしてはいけない"
        )
    }

    /// Ctrl+Z を受けると、止まる前に端末デバイスの termios を元に戻し、再開したら raw モードへ設定し直して、`TerminalApp.handle(_:)` へ `.resize` を改めて渡す。
    func testControlZSuspendsAndResumesTerminal() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        XCTAssertEqual(setTerminalSize(master, Size(width: 80, height: 24)), 0)

        // 端末デバイスへの書き出しが詰まるとループが止まるので、master から読み捨て続ける。
        let drain = OutputDrain(descriptor: master)
        drain.start()
        defer { drain.stop() }

        let terminal = Terminal(input: slave, output: slave)
        let app = SuspendRecordingApp()
        let application = Application(
            root: app,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: terminal
        )
        app.onTimeout = { [weak application] in application?.stop() }

        // 本当に止めるとテストプロセスまで止まるので、止める処理だけ差し替える。
        var isRawModeWhileStopped = true
        var isCanonicalWhileStopped = false
        application.stopProcess = {
            isRawModeWhileStopped = terminal.isRawModeEnabled
            isCanonicalWhileStopped = isCanonicalMode(slave)
        }

        var isRawModeAfterResume = false
        var isCanonicalAfterResume = true
        app.onResume = {
            isRawModeAfterResume = terminal.isRawModeEnabled
            isCanonicalAfterResume = isCanonicalMode(slave)
        }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let hasStartedLoop = app.hasStartedLoop
        let sender = Thread {
            guard hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, 0x1A)
        }
        sender.start()

        try await application.run()

        XCTAssertFalse(isRawModeWhileStopped, "止まる前に raw モードを解いていない")
        XCTAssertTrue(isCanonicalWhileStopped, "止まる前に端末デバイスの termios を戻していない")
        XCTAssertTrue(isRawModeAfterResume, "再開後に raw モードへ戻っていない")
        XCTAssertFalse(isCanonicalAfterResume, "再開後に端末デバイスの termios を設定し直していない")
        XCTAssertEqual(
            app.reportedSizes,
            [Size(width: 80, height: 24), Size(width: 80, height: 24)],
            "再開後に .resize が通知されていない"
        )
    }

    /// クラッシュしたときの手順で、端末デバイスの termios が戻り、`CrashRestorer.restoreSequence` が書き出される。
    func testCrashRestoreReturnsTerminalToNormalMode() async throws {
        var masterDescriptor: Int32 = -1
        var slaveDescriptor: Int32 = -1
        let openResult = ctui_test_open_pty(&masterDescriptor, &slaveDescriptor)
        try XCTSkipIf(openResult != 0, "疑似端末を開けない環境のため飛ばす")
        let master = masterDescriptor
        let slave = slaveDescriptor
        defer {
            close(slave)
            close(master)
        }

        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let terminal = Terminal(input: slave, output: slave)
        try terminal.enableRawMode()
        defer { terminal.restore() }
        terminal.enterAlternateScreen()

        XCTAssertFalse(isCanonicalMode(slave), "raw モードになっていない")

        // クラッシュのシグナルを送るとテストプロセスごと落ちるため、ハンドラが呼び出す `ctui_crash_restorer_restore()` を、`CrashRestorer.restoreTerminal()` から直接呼び出して確かめる。
        CrashRestorer.restoreTerminal()

        XCTAssertTrue(isCanonicalMode(slave), "クラッシュしても端末デバイスの termios が戻らない")
        XCTAssertTrue(
            drain.waitForOutput(containing: CrashRestorer.restoreSequence, timeout: 2),
            "クラッシュしても `CrashRestorer.restoreSequence` が書き出されない"
        )
    }
}

// MARK: - テスト用の `TerminalApp` に準拠する型

/// 受け取った `.resize` を記録し、キー入力に合わせて決められた動きをする `TerminalApp` に準拠する型。
private final class ResizeRecordingApp: TerminalApp {

    /// 受け取った `.resize` のサイズを届いた順に並べたもの。
    private(set) var reportedSizes: [Size] = []
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 最初のキーを受け取った `TerminalApp.handle(_:)` が、戻る前に呼び出すクロージャ。
    var onFirstKey: () -> Void = {}
    /// 入力が届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private var keyCount = 0
    private var elapsedTotal = 0.0

    var body: some View {
        Text("リサイズの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        switch event {
        case .resize(let size):
            reportedSizes.append(size)
            return .handled
        case .key:
            keyCount += 1
            guard keyCount == 1 else {
                isFinished = true
                return .handled
            }
            onFirstKey()
            return .handled
        default:
            return .ignored
        }
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 受け取った `.focus` を記録し、フォーカスを失った時点で終了する `TerminalApp` に準拠する型。
private final class FocusRecordingApp: TerminalApp {

    /// 受け取った `.focus` の値を届いた順に並べたもの。
    private(set) var focusChanges: [Bool] = []
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 通知が届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("フォーカスの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .focus(let gained) = event else { return .ignored }
        focusChanges.append(gained)
        if !gained { isFinished = true }
        return .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 枠線で囲んだ文字列を描き、`TerminalApp.update(elapsed:)` に渡された `elapsed` の合計が 0.1 秒を超えたら `onFramesDrawn` を呼び出す `TerminalApp` に準拠する型。
private final class BorderDrawingApp: TerminalApp {

    /// 渡された `elapsed` の合計が 0.1 秒を超えたときに、`TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onFramesDrawn: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("ab").border(.rounded)
    }

    func handle(_ event: InputEvent) -> EventResult { .ignored }

    func update(elapsed: Double) {
        elapsedTotal += elapsed
        if elapsedTotal > 0.1 { onFramesDrawn() }
    }
}

/// 受け取ったマウスイベントを記録し、移動が届いたら終了する `TerminalApp` に準拠する型。
private final class MouseRecordingApp: TerminalApp {

    /// 受け取ったマウスイベントを届いた順に並べたもの。
    private(set) var mouseEvents: [MouseEvent] = []
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 移動が届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("マウスの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .mouse(let mouseEvent) = event else { return .ignored }
        mouseEvents.append(mouseEvent)
        if mouseEvent.action == .move { isFinished = true }
        return .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// `View.onHover(perform:)` のクロージャに渡された値を記録し、ボタンを離したことが届いたら終了する `TerminalApp` に準拠する型。
private final class HoverRecordingApp: TerminalApp {

    /// `View.onHover(perform:)` のクロージャに渡された値を、渡された順に並べたもの。
    private(set) var hovers: [Bool] = []
    /// 届いた `.release` の数。
    private(set) var releaseCount = 0
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// ボタンを離したことが届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("ホバーの確認").onHover { [unowned self] in hovers.append($0) }
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .mouse(let mouseEvent) = event else { return .ignored }
        if mouseEvent.action == .release {
            releaseCount += 1
            isFinished = true
        }
        return .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 受け取ったキーを記録し、決めた数だけ届いたら終了する `TerminalApp` に準拠する型。
private final class KeyRecordingApp: TerminalApp {

    /// 受け取ったキーを届いた順に並べたもの。
    private(set) var keys: [KeyEvent] = []
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// キーが届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private let expectedCount: Int
    private var elapsedTotal = 0.0

    /// 終了するまでに受け取るキーの数を決めて作る。
    ///
    /// - Parameters:
    ///   - expectedCount: この数だけキーを受け取ったら終了する。
    init(expectedCount: Int) {
        self.expectedCount = expectedCount
    }

    /// 受け取るキーの数を 0 にして作る。
    convenience init() {
        self.init(expectedCount: 0)
    }

    var body: some View {
        Text("キーの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let keyEvent) = event else { return .ignored }
        keys.append(keyEvent)
        if keys.count >= expectedCount { isFinished = true }
        return .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 受け取った `.resize` を記録し、起動時に続く 2 度目（再開後の最初）の `.resize` で終了する `TerminalApp` に準拠する型。
///
/// Ctrl+Z を処理しないので、`Application` が一時停止する。
private final class SuspendRecordingApp: TerminalApp {

    /// 受け取った `.resize` のサイズを届いた順に並べたもの。
    private(set) var reportedSizes: [Size] = []
    /// `Application` を終了するかどうか。
    private(set) var isFinished = false
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 起動時に続く 2 度目の `.resize`（再開後に届く最初の `.resize`）を受け取った `TerminalApp.handle(_:)` が呼び出すクロージャ。
    var onResume: () -> Void = {}
    /// 入力が届かないまま時間切れになったときに `TerminalApp.update(elapsed:)` が呼び出すクロージャ。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("一時停止の確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .resize(let size) = event else { return .ignored }
        reportedSizes.append(size)
        guard reportedSizes.count >= 2 else { return .handled }
        onResume()
        isFinished = true
        return .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

// MARK: - 補助

private func setTerminalSize(_ descriptor: Int32, _ size: Size) -> Int32 {
    ctui_test_set_terminal_size(descriptor, Int32(size.width), Int32(size.height))
}

private func writeByte(_ descriptor: Int32, _ byte: UInt8) {
    var value = byte
    _ = write(descriptor, &value, 1)
}

private func writeBytes(_ descriptor: Int32, _ bytes: [UInt8]) {
    var values = bytes
    _ = write(descriptor, &values, values.count)
}

/// canonical モードかどうか。raw モードなら `false`。
///
/// - Parameters:
///   - descriptor: 調べるファイル記述子。
/// - Returns: canonical モードなら `true`。
private func isCanonicalMode(_ descriptor: Int32) -> Bool {
    var attributes = termios()
    guard tcgetattr(descriptor, &attributes) == 0 else { return false }
    return attributes.c_lflag & tcflag_t(ICANON) != 0
}
