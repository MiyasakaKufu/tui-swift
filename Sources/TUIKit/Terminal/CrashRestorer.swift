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
        // 同期出力が開いたまま落ちていると、後ろに続く復元が画面へ出ない。
        // 先頭から動かさない。
        ANSI.endSynchronizedUpdate
        + ANSI.disableKeyboardProtocol
        + ANSI.disableMouseTracking
        + ANSI.disableBracketedPaste
        + ANSI.disableFocusReporting
        + ANSI.exitAlternateScreen
        // `Terminal.deactivate()` のように、設定したときだけ送る形にはできない。この列は
        // 仕掛けるときに組み立てるので、後から設定されたかどうかを織り込めない。設定して
        // いなければ、形は既定のままでタイトルのスタックは空なので、送っても何も起きない。
        + ANSI.setCursorShape(.default)
        + ANSI.restoreWindowTitle
        + ANSI.reset
        + ANSI.showCursor

    /// 仕掛けた一組を指す引換券。
    ///
    /// 仕掛けた側と外す側を結び付けるための印。
    struct Ticket {
        /// 仕掛けた順に振る通し番号。
        fileprivate let serial: UInt64
    }

    /// クラッシュしたときに端末を戻すハンドラを仕掛ける。
    ///
    /// - Parameters:
    ///   - input: 端末属性を戻すファイル記述子。
    ///   - output: 制御コードを書き出すファイル記述子。
    ///   - originalAttributes: 戻す先の端末属性。
    /// - Returns: この一組を指す引換券。`disarm(_:)` に渡すと外せる。
    /// - Note: 仕掛けられるのは一組だけ。二度目からは上書きされ、前の引換券では外せなくなる。
    static func arm(input: Int32, output: Int32, originalAttributes: termios) -> Ticket {
        #if canImport(Darwin) || canImport(Glibc)
        prepareRestoreSequence()
        restoreInputDescriptor = input
        restoreOutputDescriptor = output
        restoreAttributes = originalAttributes
        installHandlers()
        armedSerial = nextSerial
        nextSerial += 1
        isArmed = 1
        return Ticket(serial: armedSerial)
        #else
        return Ticket(serial: 0)
        #endif
    }

    /// 仕掛けたハンドラを外し、前の設定へ戻す。
    ///
    /// - Parameters:
    ///   - ticket: `arm(input:output:originalAttributes:)` で受け取った引換券。
    /// - Note: 今仕掛けてあるものと違う引換券を渡しても何も起きない。二重に呼んでも安全。
    static func disarm(_ ticket: Ticket) {
        #if canImport(Darwin) || canImport(Glibc)
        guard isArmed != 0, ticket.serial == armedSerial else { return }
        isArmed = 0
        armedSerial = 0
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

/// 次に配る引換券の通し番号。
///
/// - Invariant: 一度配った番号は配り直さない。外した後の引換券が別の一組を指すことはない。
private var nextSerial: UInt64 = 1

/// 今仕掛けてある一組の通し番号。何も仕掛けていなければ 0。
private var armedSerial: UInt64 = 0

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
