#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CTUIShim

/// クラッシュで落ちる直前に、端末デバイスの termios と、端末エミュレータへ送ったモードを元に戻す型。
///
/// `fatalError` や範囲外アクセスで落ちると `defer` も `deinit` も実行されない。
/// raw モードのまま抜けるとシェルが使えなくなるので、シグナルハンドラから戻す。
enum CrashRestorer {

    /// 端末エミュレータへ送ったモードを戻すために、端末デバイスへ書き出す `String`。
    static let restoreSequence =
        // 同期出力が開いたまま落ちていると、後ろに続く復元が画面へ出ない。
        // 先頭から動かさない。
        ANSI.endSynchronizedUpdate
        + ANSI.disableKeyboardProtocol
        + ANSI.disableMouseTracking
        + ANSI.disableBracketedPaste
        + ANSI.disableFocusReporting
        + ANSI.exitAlternateScreen
        // `Terminal.deactivate()` のように、`Terminal.setCursorShape(_:)` や
        // `Terminal.setWindowTitle(_:)` を呼び出したときだけ送る形にはできない。`restoreSequence` は
        // 仕掛けるときに組み立てるので、後から呼び出されたかどうかを織り込めない。呼び出して
        // いなければタイトルのスタックは空なので、`ANSI.restoreWindowTitle` を送っても何も起きない。
        // `ANSI.setCursorShape(.default)` は、起動前に変えられていたカーソルの形も端末エミュレータの
        // デフォルトへ戻す。
        + ANSI.setCursorShape(.default)
        + ANSI.restoreWindowTitle
        + ANSI.reset
        + ANSI.showCursor

    /// クラッシュしたときとプロセスが終わるときに、端末デバイスの termios を戻し、
    /// `restoreSequence` を書き出すよう仕掛ける。
    ///
    /// - Parameters:
    ///   - input: 端末デバイスの termios を戻すファイル記述子。
    ///   - output: `restoreSequence` を書き出す、端末デバイスのファイル記述子。
    ///   - originalAttributes: 戻す先の、端末デバイスの termios。
    /// - Note: 仕掛けられるのは一組だけ。二度目からは上書きされる。
    static func arm(input: Int32, output: Int32, originalAttributes: termios) {
        #if canImport(Darwin) || canImport(Glibc)
        var attributes = originalAttributes
        let bytes = Array(restoreSequence.utf8)
        _ = bytes.withUnsafeBufferPointer { sequence in
            ctui_crash_restorer_arm(input, output, &attributes, sequence.baseAddress, sequence.count)
        }
        #endif
    }

    /// 仕掛けたハンドラを外し、前の設定へ戻す。
    ///
    /// - Note: 二重に呼び出しても安全。
    static func disarm() {
        #if canImport(Darwin) || canImport(Glibc)
        ctui_crash_restorer_disarm()
        #endif
    }

    /// `arm(input:output:originalAttributes:)` に渡した端末デバイスへ `restoreSequence` を書き出し、termios を今すぐ戻す。
    static func restoreTerminal() {
        #if canImport(Darwin) || canImport(Glibc)
        ctui_crash_restorer_restore()
        #endif
    }
}
