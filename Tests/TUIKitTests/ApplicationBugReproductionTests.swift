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
final class ApplicationBugReproductionTests: XCTestCase {

    /// イベントを処理している最中に端末サイズが変わっても `.resize` が届く。
    func testResizeDuringEventHandlingIsReported() throws {
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

        try application.run()

        XCTAssertEqual(component.reportedSizes, [initialSize, resizedSize])
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

/// pty の master 側に溜まる出力を読み捨てるスレッド。
private final class OutputDrain {
    private let descriptor: Int32
    private let stopped = Latch()

    init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    func start() {
        let descriptor = self.descriptor
        let stopped = self.stopped
        Thread {
            var bytes = [UInt8](repeating: 0, count: 4096)
            while !stopped.isSet {
                var descriptors = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptors, 1, 50) > 0 else { continue }
                if read(descriptor, &bytes, bytes.count) <= 0 { break }
            }
        }.start()
    }

    func stop() {
        stopped.set()
    }
}

private func setTerminalSize(_ descriptor: Int32, _ size: Size) -> Int32 {
    ctui_test_set_terminal_size(descriptor, Int32(size.width), Int32(size.height))
}

private func writeByte(_ descriptor: Int32, _ byte: UInt8) {
    var value = byte
    _ = write(descriptor, &value, 1)
}
