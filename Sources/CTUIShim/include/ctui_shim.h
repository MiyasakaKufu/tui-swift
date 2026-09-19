#ifndef CTUI_SHIM_H
#define CTUI_SHIM_H

#include <signal.h>

// Swift から C の可変長引数関数 `ioctl` を直接呼ぶことはできない。
// この宣言を消して Swift 側から `ioctl` を呼んではいけない。

/// 端末のウィンドウサイズを取得する。
///
/// - Parameters:
///   - fd: 問い合わせるファイル記述子。
///   - columns: 桁数の書き込み先。`NULL` なら書き込まない。
///   - rows: 行数の書き込み先。`NULL` なら書き込まない。
/// - Returns: 成功なら 0、失敗なら -1。
int ctui_terminal_size(int fd, int *columns, int *rows);

// `struct sigaction` のハンドラは共用体の中にあり、Swift からは組み立てられない。
// `signal(3)` で代用してはいけない。前の設定を `struct sigaction` として受け取れず、
// Swift ランタイムが仕掛けたクラッシュ時のハンドラへ戻せなくなる。

/// シグナルハンドラを登録し、前の設定を返す。
///
/// - Parameters:
///   - signal_number: 登録するシグナル番号。
///   - handler: 登録するハンドラ。
///   - previous: 前の設定の書き込み先。`NULL` なら書き込まない。
/// - Returns: 成功なら 0、失敗なら -1。
/// - Note: ハンドラの中から同じシグナルを送り直せるよう `SA_NODEFER` を立てる。
int ctui_install_signal_handler(int signal_number,
                                void (*handler)(int),
                                struct sigaction *previous);

/// シグナルの設定を前の設定へ戻す。
///
/// - Parameters:
///   - signal_number: 戻すシグナル番号。
///   - previous: 戻す先の設定。
/// - Returns: 成功なら 0、失敗なら -1。
int ctui_restore_signal_handler(int signal_number, const struct sigaction *previous);

#endif /* CTUI_SHIM_H */
