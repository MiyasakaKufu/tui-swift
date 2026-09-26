#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import Foundation
import Synchronization

/// スレッドをまたいで一度だけ立てるフラグ。
final class Latch: Sendable {
    private let isRaised = Atomic(false)

    func set() {
        isRaised.store(true, ordering: .releasing)
    }

    var isSet: Bool {
        isRaised.load(ordering: .acquiring)
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
final class OutputDrain: Sendable {
    private let descriptor: Int32
    private let recordsOutput: Bool
    private let stopped = Latch()
    private let finished = Latch()
    private let recorded = Mutex<[UInt8]>([])

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

    /// それまでに読んで覚えた内容を捨てる。
    func reset() {
        recorded.withLock { $0.removeAll() }
    }

    private var output: String {
        recorded.withLock { String(decoding: $0, as: UTF8.self) }
    }

    private func record(_ bytes: ArraySlice<UInt8>) {
        guard recordsOutput else { return }
        recorded.withLock { $0.append(contentsOf: bytes) }
    }
}
