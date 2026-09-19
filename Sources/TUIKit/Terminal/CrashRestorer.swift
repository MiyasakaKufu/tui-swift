#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CTUIShim

/// クラッシュで落ちる直前に端末を戻す仕組み。
///
/// `fatalError` や範囲外アクセスで落ちると `defer` も `deinit` も実行されない。
/// raw モードのまま抜けるとシェルが使えなくなるので、シグナルハンドラから戻す。
enum CrashRestorer {

    /// 端末を戻すために書き出す制御コード。
    static let restoreSequence =
        ANSI.disableMouseTracking
        + ANSI.disableBracketedPaste
        + ANSI.disableFocusReporting
        + ANSI.exitAlternateScreen
        + ANSI.reset
        + ANSI.showCursor

    /// クラッシュしたときに端末を戻すハンドラを仕掛ける。
    ///
    /// - Parameters:
    ///   - input: 端末属性を戻すファイル記述子。
    ///   - output: 制御コードを書き出すファイル記述子。
    ///   - originalAttributes: 戻す先の端末属性。
    /// - Note: 仕掛けられるのは一組だけ。二度目からは上書きされる。
    static func arm(input: Int32, output: Int32, originalAttributes: termios) {
        #if canImport(Darwin) || canImport(Glibc)
        prepareRestoreSequence()
        restoreInputDescriptor = input
        restoreOutputDescriptor = output
        restoreAttributes = originalAttributes
        installHandlers()
        isArmed = 1
        #endif
    }

    /// 仕掛けたハンドラを外し、前の設定へ戻す。
    ///
    /// - Note: 二重に呼んでも安全。
    static func disarm() {
        #if canImport(Darwin) || canImport(Glibc)
        guard isArmed != 0 else { return }
        isArmed = 0
        restoreInputDescriptor = -1
        restoreOutputDescriptor = -1
        removeHandlers()
        #endif
    }

    /// 仕掛けた端末を今すぐ戻す。
    ///
    /// - Note: シグナルハンドラから呼ぶため、非同期シグナル安全な `write(2)` と
    ///   `tcsetattr(3)` しか使わない。文字列やコレクションには触れない。
    static func restoreTerminal() {
        #if canImport(Darwin) || canImport(Glibc)
        guard isArmed != 0 else { return }

        if let sequence = restoreSequenceBytes, restoreOutputDescriptor >= 0 {
            writeAllBytes(restoreOutputDescriptor, sequence, restoreSequenceLength)
        }
        if restoreInputDescriptor >= 0 {
            _ = tcsetattr(restoreInputDescriptor, TCSAFLUSH, &restoreAttributes)
        }
        #endif
    }
}

#if canImport(Darwin) || canImport(Glibc)

/// クラッシュとして扱うシグナル。
///
/// Swift の `fatalError` や範囲外アクセスは、命令トラップとして SIGILL / SIGTRAP になる。
private let crashSignalNumbers: [Int32] = [SIGILL, SIGTRAP, SIGABRT, SIGBUS, SIGSEGV]

/// ハンドラを仕掛けてあるか。シグナルハンドラから触れるのはこの種のフラグだけ。
private var isArmed: sig_atomic_t = 0

private var restoreInputDescriptor: Int32 = -1
private var restoreOutputDescriptor: Int32 = -1
private var restoreAttributes = termios()

/// 書き出す制御コード。ハンドラの中では文字列を扱えないので、仕掛けるときに用意する。
private var restoreSequenceBytes: UnsafeMutablePointer<UInt8>?
private var restoreSequenceLength = 0

/// ハンドラを仕掛けたシグナルと、その前の設定。並びは対応している。
private var armedSignalNumbers: UnsafeMutablePointer<Int32>?
private var previousActions: UnsafeMutablePointer<sigaction>?
private var armedSignalCount = 0

private func handleCrashSignal(_ signalNumber: Int32) {
    CrashRestorer.restoreTerminal()

    // 前の設定へ戻してから送り直す。こうすると Swift ランタイムのクラッシュ表示や
    // コアダンプが、何も仕掛けなかったときと同じように行われる。
    restorePreviousAction(for: signalNumber)
    _ = raise(signalNumber)
}

/// 書き出す制御コードを用意する。
///
/// - Note: 二度目以降の呼び出しでは何もしない。
private func prepareRestoreSequence() {
    guard restoreSequenceBytes == nil else { return }

    let bytes = Array(CrashRestorer.restoreSequence.utf8)
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
    bytes.withUnsafeBufferPointer { source in
        guard let base = source.baseAddress else { return }
        buffer.initialize(from: base, count: source.count)
    }
    restoreSequenceBytes = buffer
    restoreSequenceLength = bytes.count
}

/// クラッシュのシグナルにハンドラを仕掛ける。
///
/// - Note: すでに仕掛けてあれば何もしない。
private func installHandlers() {
    guard armedSignalNumbers == nil else { return }

    let capacity = crashSignalNumbers.count
    let numbers = UnsafeMutablePointer<Int32>.allocate(capacity: capacity)
    let actions = UnsafeMutablePointer<sigaction>.allocate(capacity: capacity)
    actions.initialize(repeating: sigaction(), count: capacity)

    var installed = 0
    for number in crashSignalNumbers {
        guard ctui_install_signal_handler(number, handleCrashSignal, actions + installed) == 0
        else { continue }
        (numbers + installed).initialize(to: number)
        installed += 1
    }

    armedSignalNumbers = numbers
    previousActions = actions
    armedSignalCount = installed
}

/// 仕掛けたハンドラを前の設定へ戻す。
private func removeHandlers() {
    guard let numbers = armedSignalNumbers, let actions = previousActions else { return }

    for index in 0..<armedSignalCount {
        _ = ctui_restore_signal_handler(numbers[index], actions + index)
    }

    numbers.deallocate()
    actions.deinitialize(count: crashSignalNumbers.count)
    actions.deallocate()
    armedSignalNumbers = nil
    previousActions = nil
    armedSignalCount = 0
}

/// 指定したシグナルの設定を、仕掛ける前の設定へ戻す。
///
/// - Parameters:
///   - signalNumber: 戻すシグナル番号。
private func restorePreviousAction(for signalNumber: Int32) {
    guard let numbers = armedSignalNumbers, let actions = previousActions else { return }

    for index in 0..<armedSignalCount where numbers[index] == signalNumber {
        _ = ctui_restore_signal_handler(signalNumber, actions + index)
        return
    }
}

/// `write(2)` を最後まで書き切るまで繰り返す。
///
/// - Parameters:
///   - descriptor: 書き出す先のファイル記述子。
///   - bytes: 書き出すバイト列の先頭。
///   - count: 書き出すバイト数。
private func writeAllBytes(_ descriptor: Int32, _ bytes: UnsafePointer<UInt8>, _ count: Int) {
    var offset = 0
    while offset < count {
        let written = write(descriptor, bytes + offset, count - offset)
        if written > 0 {
            offset += written
        } else if written < 0 && errno == EINTR {
            continue
        } else {
            break
        }
    }
}

#endif
