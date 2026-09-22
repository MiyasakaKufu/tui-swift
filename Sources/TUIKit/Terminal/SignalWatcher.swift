#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

import CTUIShim

/// イベント待ちを起こす。
///
/// - See: [The Open Group Base Specifications](https://pubs.opengroup.org/onlinepubs/9799919799/) の
///   「Signal Concepts」にある Async-Signal-Safe Functions。
private func wakeUpEventLoop() {
    ctui_signal_wake_up()
}

private func handleWindowResizeSignal(_ signalNumber: Int32) {
    ctui_signal_set_window_resize()
}

private func handleTerminationSignal(_ signalNumber: Int32) {
    ctui_signal_set_termination()
}

private func handleSuspendSignal(_ signalNumber: Int32) {
    ctui_signal_set_suspend()
}

private func handleContinueSignal(_ signalNumber: Int32) {
    ctui_signal_set_continue()
}

/// ウィンドウサイズ変更・終了・一時停止のシグナルの監視。
public enum SignalWatcher {

    /// SIGWINCH、終了シグナル、SIGTSTP / SIGCONT のハンドラを登録する。
    ///
    /// 終了シグナルは SIGTERM / SIGHUP / SIGINT / SIGQUIT。既定の動作のまま受けると、
    /// `Application` の終了処理が行われず、端末が raw モードのまま残る。
    ///
    /// - Postcondition: `wakeupDescriptor` が使えるようになる。SIGPIPE は無視される。
    public static func install() {
        #if canImport(Darwin) || canImport(Glibc)
        openWakeupPipe()
        _ = signal(SIGWINCH, handleWindowResizeSignal)
        _ = signal(SIGTERM, handleTerminationSignal)
        _ = signal(SIGHUP, handleTerminationSignal)
        _ = signal(SIGINT, handleTerminationSignal)
        _ = signal(SIGQUIT, handleTerminationSignal)
        _ = signal(SIGTSTP, handleSuspendSignal)
        _ = signal(SIGCONT, handleContinueSignal)
        // 出力先が閉じられてもプロセスを落とさない。
        _ = signal(SIGPIPE, SIG_IGN)
        #endif
    }

    /// 自分自身を止め、再開されるまで戻らない。
    ///
    /// - Precondition: 呼ぶ前に端末を元へ戻しておく。
    /// - Postcondition: 戻るときに SIGTSTP のハンドラを登録し直す。
    public static func stopProcess() {
        #if canImport(Darwin) || canImport(Glibc)
        _ = signal(SIGTSTP, SIG_DFL)
        // プロセスグループごと止めてはいけない。同じ端末を使う他のプロセスまで巻き込む。
        _ = raise(SIGTSTP)
        _ = signal(SIGTSTP, handleSuspendSignal)
        #endif
    }

    /// イベント待ちを起こす。
    ///
    /// シグナル以外の理由でイベントループを進めたいときに呼ぶ。
    ///
    /// - Note: `install()` を呼ぶ前は何も起こらない。
    static func wakeUp() {
        wakeUpEventLoop()
    }

    /// シグナルが届いたことを知らせるパイプの読み取り側。
    ///
    /// `install()` を呼ぶ前や、パイプを作れなかったときは `nil`。
    ///
    /// - Note: 非ブロッキングなので、読み取り可能になった後は EAGAIN になるまで読み捨てられる。
    public static var wakeupDescriptor: Int32? {
        let descriptor = ctui_signal_wakeup_read_descriptor()
        return descriptor >= 0 ? descriptor : nil
    }

    /// ウィンドウサイズ変更の通知を受け取る。
    ///
    /// - Returns: 前回の呼び出し以降に SIGWINCH が届いていれば `true`。
    /// - Postcondition: 同じ通知を二度受け取ることはない。
    public static func consumeWindowResize() -> Bool {
        return ctui_signal_consume_window_resize() != 0
    }

    /// 終了シグナルの通知を受け取る。
    ///
    /// - Returns: 前回の呼び出し以降に SIGTERM / SIGHUP / SIGINT / SIGQUIT の
    ///   いずれかが届いていれば `true`。
    /// - Postcondition: 同じ通知を二度受け取ることはない。
    public static func consumeTermination() -> Bool {
        return ctui_signal_consume_termination() != 0
    }

    /// 一時停止シグナルの通知を受け取る。
    ///
    /// - Returns: 前回の呼び出し以降に SIGTSTP が届いていれば `true`。
    /// - Postcondition: 同じ通知を二度受け取ることはない。
    public static func consumeSuspend() -> Bool {
        return ctui_signal_consume_suspend() != 0
    }

    /// 再開シグナルの通知を受け取る。
    ///
    /// - Returns: 前回の呼び出し以降に SIGCONT が届いていれば `true`。
    /// - Postcondition: 同じ通知を二度受け取ることはない。
    /// - Note: 捕まえられない SIGSTOP で止められた場合も、再開されればこれで分かる。
    public static func consumeContinue() -> Bool {
        return ctui_signal_consume_continue() != 0
    }
}

#if canImport(Darwin) || canImport(Glibc)

/// 自己パイプを用意する。
///
/// - Note: 二度目以降の呼び出しでは何もしない。
private func openWakeupPipe() {
    guard ctui_signal_wakeup_read_descriptor() < 0 else { return }

    var descriptors: [Int32] = [-1, -1]
    guard pipe(&descriptors) == 0 else { return }

    // ブロッキングのままにしてはいけない。
    // パイプが詰まると、ハンドラ内の `write(2)` と読み捨てのための `read(2)` が止まる。
    makeNonBlocking(descriptors[0])
    makeNonBlocking(descriptors[1])
    closeOnExec(descriptors[0])
    closeOnExec(descriptors[1])

    ctui_signal_set_wakeup_pipe(descriptors[0], descriptors[1])
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
