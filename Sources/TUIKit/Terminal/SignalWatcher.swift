#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// シグナルハンドラから触れるフラグ。
/// シグナルハンドラ内で行えるのはこの種のフラグ更新だけなので、実際の処理はイベントループ側で行う。
private var windowResizeFlag: sig_atomic_t = 0
private var terminationFlag: sig_atomic_t = 0

/// 自己パイプ（self-pipe）の両端。
///
/// フラグを立てるだけでは、イベント待ちの `poll(2)` に入る直前に届いたシグナルを
/// 取りこぼす。`poll` は割り込まれないため、次の入力が来るまでループが動かない。
/// そこでシグナルハンドラからパイプへ 1 バイト書き込み、そのパイプを入力と一緒に
/// 待つことで、シグナルが届いた時点でイベント待ちを終わらせる。
private var wakeupReadDescriptor: Int32 = -1
private var wakeupWriteDescriptor: Int32 = -1

/// イベント待ちを起こす。
///
/// シグナルハンドラから呼べるのは非同期シグナル安全な操作だけ。`write(2)` は安全だが
/// `errno` を書き換えるため、割り込んだ処理に影響しないよう退避して戻す。
private func wakeUpEventLoop() {
    let descriptor = wakeupWriteDescriptor
    guard descriptor >= 0 else { return }
    let savedErrno = errno
    var byte: UInt8 = 0
    // パイプが詰まっていて書けなくても構わない。起こす合図は 1 バイトあれば足りる。
    _ = write(descriptor, &byte, 1)
    errno = savedErrno
}

private func handleWindowResizeSignal(_ signalNumber: Int32) {
    windowResizeFlag = 1
    wakeUpEventLoop()
}

private func handleTerminationSignal(_ signalNumber: Int32) {
    terminationFlag = 1
    wakeUpEventLoop()
}

/// ウィンドウサイズ変更・終了シグナルの監視。
public enum SignalWatcher {

    /// SIGWINCH と SIGTERM / SIGHUP のハンドラを登録する。
    public static func install() {
        #if canImport(Darwin) || canImport(Glibc)
        openWakeupPipe()
        _ = signal(SIGWINCH, handleWindowResizeSignal)
        _ = signal(SIGTERM, handleTerminationSignal)
        _ = signal(SIGHUP, handleTerminationSignal)
        // 出力先が閉じられてもプロセスを落とさない。
        _ = signal(SIGPIPE, SIG_IGN)
        #endif
    }

    /// シグナルが届いたことを知らせるパイプの読み取り側。
    ///
    /// `install()` より前や、パイプを作れなかった場合は `nil`。
    /// 非ブロッキングなので、読めるようになった後は EAGAIN まで読み捨てられる。
    public static var wakeupDescriptor: Int32? {
        wakeupReadDescriptor >= 0 ? wakeupReadDescriptor : nil
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

#if canImport(Darwin) || canImport(Glibc)

/// 自己パイプを用意する。二度目以降は何もしない。
private func openWakeupPipe() {
    guard wakeupReadDescriptor < 0 else { return }

    var descriptors: [Int32] = [-1, -1]
    guard pipe(&descriptors) == 0 else { return }

    // ハンドラ内の `write(2)` と、読み捨てのための `read(2)` が止まらないようにする。
    makeNonBlocking(descriptors[0])
    makeNonBlocking(descriptors[1])
    closeOnExec(descriptors[0])
    closeOnExec(descriptors[1])

    wakeupReadDescriptor = descriptors[0]
    // 書き込み側は最後に入れる。ハンドラはこの値だけを見るため、
    // 途中の状態で書き込まれることがない。
    wakeupWriteDescriptor = descriptors[1]
}

private func makeNonBlocking(_ descriptor: Int32) {
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0 else { return }
    _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
}

private func closeOnExec(_ descriptor: Int32) {
    let flags = fcntl(descriptor, F_GETFD)
    guard flags >= 0 else { return }
    _ = fcntl(descriptor, F_SETFD, flags | FD_CLOEXEC)
}

#endif
