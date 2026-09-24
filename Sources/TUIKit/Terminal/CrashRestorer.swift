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
        // `Terminal.deactivate()` のように、設定したときだけ送る形にはできない。この制御コードは
        // 仕掛けるときに組み立てるので、後から設定されたかどうかを織り込めない。設定して
        // いなければ、形は既定のままでタイトルのスタックは空なので、送っても何も起きない。
        + ANSI.setCursorShape(.default)
        + ANSI.restoreWindowTitle
        + ANSI.reset
        + ANSI.showCursor

    /// クラッシュしたときとプロセスが終わるときに、termios を戻し、
    /// 打ち消す制御コードを書き出すよう仕掛ける。
    ///
    /// - Parameters:
    ///   - input: 端末属性を戻すファイル記述子。
    ///   - output: 制御コードを書き出すファイル記述子。
    ///   - originalAttributes: 戻す先の端末属性。
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
    /// - Note: 二重に呼んでも安全。
    static func disarm() {
        #if canImport(Darwin) || canImport(Glibc)
        ctui_crash_restorer_disarm()
        #endif
    }

    /// 仕掛けた端末を今すぐ戻す。
    static func restoreTerminal() {
        #if canImport(Darwin) || canImport(Glibc)
        ctui_crash_restorer_restore()
        #endif
    }
}
