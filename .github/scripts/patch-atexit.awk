# H17 の計測。`CrashRestorer.arm()` の中でプロセス終了時の後片付けを仕掛ける。
# `restoreTerminal()` は非隔離で `write(2)` と `tcsetattr` しか使わないので、
# `atexit(3)` のハンドラからも呼べる。
/^        installHandlers\(\)$/ {
    print
    print "        installExitHandler()"
    next
}
/^#if canImport\(Darwin\) \|\| canImport\(Glibc\)$/ && !done {
    print
    print ""
    print "/// プロセス終了時の後片付けを仕掛けたか。"
    print "private var isExitHandlerInstalled = false"
    print ""
    print "/// プロセス終了時に端末を戻す。`restore()` を呼ばずに捨てられた場合の受け皿。"
    print "private func installExitHandler() {"
    print "    guard !isExitHandlerInstalled else { return }"
    print "    isExitHandlerInstalled = true"
    print "    atexit { CrashRestorer.restoreTerminal() }"
    print "}"
    done = 1
    next
}
{ print }
