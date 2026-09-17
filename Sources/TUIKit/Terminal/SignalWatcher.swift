#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// シグナルハンドラから触れるフラグ。
/// シグナルハンドラ内で行えるのはこの種のフラグ更新だけなので、実際の処理はイベントループ側で行う。
private var windowResizeFlag: sig_atomic_t = 0
private var terminationFlag: sig_atomic_t = 0

private func handleWindowResizeSignal(_ signalNumber: Int32) {
    windowResizeFlag = 1
}

private func handleTerminationSignal(_ signalNumber: Int32) {
    terminationFlag = 1
}

/// ウィンドウサイズ変更・終了シグナルの監視。
public enum SignalWatcher {

    /// SIGWINCH と SIGTERM / SIGHUP のハンドラを登録する。
    public static func install() {
        #if canImport(Darwin) || canImport(Glibc)
        _ = signal(SIGWINCH, handleWindowResizeSignal)
        _ = signal(SIGTERM, handleTerminationSignal)
        _ = signal(SIGHUP, handleTerminationSignal)
        // 出力先が閉じられてもプロセスを落とさない。
        _ = signal(SIGPIPE, SIG_IGN)
        #endif
    }

    /// ウィンドウサイズ変更が発生していれば `true` を返し、フラグを下ろす。
    public static func consumeWindowResize() -> Bool {
        if windowResizeFlag != 0 {
            windowResizeFlag = 0
            return true
        }
        return false
    }

    /// 終了シグナルを受け取っていれば `true` を返し、フラグを下ろす。
    public static func consumeTermination() -> Bool {
        if terminationFlag != 0 {
            terminationFlag = 0
            return true
        }
        return false
    }
}
