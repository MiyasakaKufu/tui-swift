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

    /// イベントを処理している最中に端末サイズが変わっても `.resize` が届く。
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

        // 出力先が詰まるとループが止まるので、master 側は読み捨て続ける。
        let drain = OutputDrain(descriptor: master)
        drain.start()
        defer { drain.stop() }

        let component = ResizeRecordingComponent()
        let application = Application(
            root: component,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        component.onFirstKey = {
            _ = setTerminalSize(master, resizedSize)
            raise(SIGWINCH)
        }
        component.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let sender = Thread {
            guard component.hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, UInt8(ascii: "a"))
            Thread.sleep(forTimeInterval: 0.2)
            writeByte(master, UInt8(ascii: "b"))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(component.reportedSizes, [initialSize, resizedSize])
    }

    /// `reportsFocus` を有効にすると `.focus` が届き、終了時に通知が止まる。
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

        // 出力先が詰まるとループが止まるので、master 側は読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let component = FocusRecordingComponent()
        let application = Application(
            root: component,
            options: ApplicationOptions(
                usesAlternateScreen: false,
                reportsFocus: true,
                frameInterval: 1.0 / 60
            ),
            terminal: Terminal(input: slave, output: slave)
        )
        component.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let sender = Thread {
            guard component.hasStartedLoop.wait(timeout: 5) else { return }
            writeBytes(master, Array("\u{1B}[I".utf8))
            Thread.sleep(forTimeInterval: 0.2)
            writeBytes(master, Array("\u{1B}[O".utf8))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(component.focusChanges, [true, false])
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableFocusReporting, timeout: 2),
            "フォーカス通知を有効にするシーケンスが送られていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableFocusReporting, timeout: 2),
            "終了時にフォーカス通知が止められていない"
        )
    }

    /// `ambiguousWidth` の指定どおりの桁数で枠線が描かれる。
    func testApplicationDrawsBorderWithTheAmbiguousWidthOption() async throws {
        // 枠全体（`╭──╮`）を探してはいけない。ルートのビューは端末全体に広がるので、
        // 角と角の間は端末の幅まで伸び、その並びは出力に現れない。
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

            // 出力先が詰まるとループが止まるので、master 側は読み続ける。
            let drain = OutputDrain(descriptor: master, recordsOutput: true)
            drain.start()
            defer { drain.stop() }

            let component = BorderDrawingComponent()
            let application = Application(
                root: component,
                options: ApplicationOptions(
                    usesAlternateScreen: false,
                    usesKeyboardProtocol: false,
                    frameInterval: 1.0 / 60,
                    ambiguousWidth: ambiguous
                ),
                terminal: Terminal(input: slave, output: slave)
            )
            component.onFramesDrawn = { [weak application] in application?.stop() }

            try await application.run()

            for fragment in fragments {
                XCTAssertTrue(
                    drain.waitForOutput(containing: fragment, timeout: 2),
                    "\(ambiguous) のとき \(fragment) が描かれていない"
                )
            }
        }
    }

    /// `mouseTracking` が `.motion` なら、ボタンを押していない移動が `.move` として届く。
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

        // 出力先が詰まるとループが止まるので、master 側は読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let component = MouseRecordingComponent()
        let application = Application(
            root: component,
            options: ApplicationOptions(
                usesAlternateScreen: false,
                mouseTracking: .motion,
                frameInterval: 1.0 / 60
            ),
            terminal: Terminal(input: slave, output: slave)
        )
        component.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let sender = Thread {
            guard component.hasStartedLoop.wait(timeout: 5) else { return }
            writeBytes(master, Array("\u{1B}[<35;4;2M".utf8))
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(
            component.mouseEvents,
            [MouseEvent(position: Point(x: 3, y: 1), button: .none, action: .move)]
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableMouseMotionTracking, timeout: 2),
            "移動追跡を有効にするシーケンスが送られていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableMouseTracking, timeout: 2),
            "終了時にマウスの通知が止められていない"
        )
    }

    /// 対応する端末では kitty keyboard protocol を有効にし、Ctrl+I と Tab を区別する。
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

        // 出力先が詰まるとループが止まるので、master 側は読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let component = KeyRecordingComponent(expectedCount: 2)
        let application = Application(
            root: component,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        component.onTimeout = { [weak application] in application?.stop() }

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
            component.keys,
            [KeyEvent(.character("i"), modifiers: .control), KeyEvent(.tab)],
            "Ctrl+I と Tab が区別されていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.enableKeyboardProtocol, timeout: 2),
            "対応している端末で有効にするシーケンスが送られていない"
        )
        XCTAssertTrue(
            drain.waitForOutput(containing: ANSI.disableKeyboardProtocol, timeout: 2),
            "終了時に元の形式へ戻していない"
        )
    }

    /// 応答しない端末では kitty keyboard protocol を有効にしない。
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

        // 出力先が詰まるとループが止まるので、master 側は読み続ける。
        let drain = OutputDrain(descriptor: master, recordsOutput: true)
        drain.start()
        defer { drain.stop() }

        let component = KeyRecordingComponent(expectedCount: 1)
        let application = Application(
            root: component,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: Terminal(input: slave, output: slave)
        )
        component.onTimeout = { [weak application] in application?.stop() }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let sender = Thread {
            guard component.hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, 0x09)
        }
        sender.start()

        try await application.run()

        XCTAssertEqual(component.keys, [KeyEvent(.tab)], "従来どおりの形式で届いていない")
        XCTAssertFalse(
            drain.waitForOutput(containing: ANSI.enableKeyboardProtocol, timeout: 0.5),
            "応答しない端末で有効にしてはいけない"
        )
    }

    /// Ctrl+Z を受けると端末をシェルへ返し、再開したら設定と画面を取り戻す。
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

        // 出力先が詰まるとループが止まるので、master 側は読み捨て続ける。
        let drain = OutputDrain(descriptor: master)
        drain.start()
        defer { drain.stop() }

        let terminal = Terminal(input: slave, output: slave)
        let component = SuspendRecordingComponent()
        let application = Application(
            root: component,
            options: ApplicationOptions(usesAlternateScreen: false, frameInterval: 1.0 / 60),
            terminal: terminal
        )
        component.onTimeout = { [weak application] in application?.stop() }

        // 本当に止めるとテストプロセスまで止まるので、止める処理だけ差し替える。
        var isRawModeWhileStopped = true
        var isCanonicalWhileStopped = false
        application.stopProcess = {
            isRawModeWhileStopped = terminal.isRawModeEnabled
            isCanonicalWhileStopped = isCanonicalMode(slave)
        }

        var isRawModeAfterResume = false
        var isCanonicalAfterResume = true
        component.onResume = {
            isRawModeAfterResume = terminal.isRawModeEnabled
            isCanonicalAfterResume = isCanonicalMode(slave)
        }

        // raw モードの設定は入力待ちのバイト列を捨てるため、ループが回り始めてから送る。
        let sender = Thread {
            guard component.hasStartedLoop.wait(timeout: 5) else { return }
            writeByte(master, 0x1A)
        }
        sender.start()

        try await application.run()

        XCTAssertFalse(isRawModeWhileStopped, "止まる前に raw モードを解いていない")
        XCTAssertTrue(isCanonicalWhileStopped, "止まる前に端末属性を戻していない")
        XCTAssertTrue(isRawModeAfterResume, "再開後に raw モードへ戻っていない")
        XCTAssertFalse(isCanonicalAfterResume, "再開後に端末属性を設定し直していない")
        XCTAssertEqual(
            component.reportedSizes,
            [Size(width: 80, height: 24), Size(width: 80, height: 24)],
            "再開後に .resize が通知されていない"
        )
    }

    /// クラッシュしたときの手順で端末が元に戻る。
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

        // クラッシュのシグナルを送るとテストプロセスごと落ちるため、
        // ハンドラが呼ぶ処理だけを直接確かめる。
        CrashRestorer.restoreTerminal()

        XCTAssertTrue(isCanonicalMode(slave), "クラッシュしても端末属性が戻らない")
        XCTAssertTrue(
            drain.waitForOutput(containing: CrashRestorer.restoreSequence, timeout: 2),
            "クラッシュしても復元用の制御コードが書き出されない"
        )
    }
}

// MARK: - テスト用のコンポーネント

/// 受け取った `.resize` を記録し、キー入力に合わせて決められた動きをするコンポーネント。
private final class ResizeRecordingComponent: Component {

    /// 受け取った `.resize` のサイズを届いた順に並べたもの。
    private(set) var reportedSizes: [Size] = []
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 最初のキーを処理している最中に呼ばれる。
    var onFirstKey: () -> Void = {}
    /// 入力が届かないまま時間切れになったときの脱出口。
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
            guard keyCount == 1 else { return .quit }
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

/// 受け取った `.focus` を記録し、フォーカスを失った時点で終了するコンポーネント。
private final class FocusRecordingComponent: Component {

    /// 受け取った `.focus` の値を届いた順に並べたもの。
    private(set) var focusChanges: [Bool] = []
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 通知が届かないまま時間切れになったときの脱出口。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("フォーカスの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .focus(let gained) = event else { return .ignored }
        focusChanges.append(gained)
        return gained ? .handled : .quit
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 枠線で囲んだ文字列を描き、何フレームか回ったら終了するコンポーネント。
private final class BorderDrawingComponent: Component {

    /// 何フレームか回ったときに呼ばれる。
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

/// 受け取ったマウスイベントを記録し、移動が届いたら終了するコンポーネント。
private final class MouseRecordingComponent: Component {

    /// 受け取ったマウスイベントを届いた順に並べたもの。
    private(set) var mouseEvents: [MouseEvent] = []
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 移動が届かないまま時間切れになったときの脱出口。
    var onTimeout: () -> Void = {}

    private var elapsedTotal = 0.0

    var body: some View {
        Text("マウスの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .mouse(let mouseEvent) = event else { return .ignored }
        mouseEvents.append(mouseEvent)
        return mouseEvent.action == .move ? .quit : .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 受け取ったキーを記録し、決めた数だけ届いたら終了するコンポーネント。
private final class KeyRecordingComponent: Component {

    /// 受け取ったキーを届いた順に並べたもの。
    private(set) var keys: [KeyEvent] = []
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// キーが届かないまま時間切れになったときの脱出口。
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

    var body: some View {
        Text("キーの確認")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let keyEvent) = event else { return .ignored }
        keys.append(keyEvent)
        return keys.count >= expectedCount ? .quit : .handled
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

/// 受け取った `.resize` を記録し、再開後の 2 度目で終了するコンポーネント。
///
/// Ctrl+Z を処理しないので、`Application` が一時停止する。
private final class SuspendRecordingComponent: Component {

    /// 受け取った `.resize` のサイズを届いた順に並べたもの。
    private(set) var reportedSizes: [Size] = []
    /// イベントループが 1 周したら立つ。
    let hasStartedLoop = Latch()

    /// 一時停止から戻って `.resize` が届いたときに呼ばれる。
    var onResume: () -> Void = {}
    /// 入力が届かないまま時間切れになったときの脱出口。
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
        return .quit
    }

    func update(elapsed: Double) {
        hasStartedLoop.set()
        elapsedTotal += elapsed
        if elapsedTotal > 5 { onTimeout() }
    }
}

// MARK: - 補助

/// スレッドをまたいで一度だけ立てるフラグ。
private final class Latch {
    private let lock = NSLock()
    private var isRaised = false

    func set() {
        lock.lock()
        isRaised = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRaised
    }

    /// フラグが立つまで待つ。
    ///
    /// - Parameters:
    ///   - timeout: 待つ秒数の上限。
    /// - Returns: 時間内に立てば `true`。
    func wait(timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !isSet {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }
}

/// pty の master 側に溜まる出力を読み続けるスレッド。
///
/// 求められたときだけ読んだ内容を覚え、それ以外は読み捨てる。
private final class OutputDrain {
    private let descriptor: Int32
    private let recordsOutput: Bool
    private let stopped = Latch()
    private let finished = Latch()
    private let lock = NSLock()
    private var recorded: [UInt8] = []

    init(descriptor: Int32, recordsOutput: Bool = false) {
        self.descriptor = descriptor
        self.recordsOutput = recordsOutput
    }

    func start() {
        let descriptor = self.descriptor
        let stopped = self.stopped
        let finished = self.finished
        Thread { [weak self] in
            defer { finished.set() }
            var bytes = [UInt8](repeating: 0, count: 4096)
            while !stopped.isSet {
                var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptors, 1, 50) > 0 else { continue }
                let count = read(descriptor, &bytes, bytes.count)
                if count <= 0 { break }
                self?.record(bytes[0..<count])
            }
        }.start()
    }

    func stop() {
        stopped.set()
        // 読み取りの終わりを待たずに戻してはいけない。スレッドが `poll(2)` の中に残ったまま
        // 記述子が閉じられ、次に開いた疑似端末が同じ番号を使うと、その出力を横取りする。
        _ = finished.wait(timeout: 1)
    }

    /// 読んだ内容に部分列が現れるまで待つ。
    ///
    /// - Parameters:
    ///   - sequence: 探す部分列。
    ///   - timeout: 待つ秒数の上限。
    /// - Returns: 時間内に現れれば `true`。
    func waitForOutput(containing sequence: String, timeout: Double) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while output.range(of: sequence) == nil {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.005)
        }
        return true
    }

    private var output: String {
        lock.lock()
        defer { lock.unlock() }
        return String(decoding: recorded, as: UTF8.self)
    }

    private func record(_ bytes: ArraySlice<UInt8>) {
        guard recordsOutput else { return }
        lock.lock()
        recorded.append(contentsOf: bytes)
        lock.unlock()
    }
}

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
