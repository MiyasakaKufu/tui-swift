#ifndef CTUI_TEST_SUPPORT_H
#define CTUI_TEST_SUPPORT_H

/// 疑似端末（pty）を開き、マスタ側とスレーブ側の記述子を返す。
///
/// `posix_openpt` などは Swift の Glibc モジュールから見えないため、C 側に置いている。
/// 成功時は 0、失敗時は -1 を返す。
int ctui_open_pty(int *master, int *slave);

/// 端末のウィンドウサイズを設定する。
///
/// 疑似端末のマスタ側に対して使い、スレーブ側で動くプログラムから見えるサイズを変える。
/// `ioctl` は可変長引数のため Swift から直接呼べない。成功時は 0、失敗時は -1 を返す。
int ctui_set_terminal_size(int fd, int columns, int rows);

#endif /* CTUI_TEST_SUPPORT_H */
