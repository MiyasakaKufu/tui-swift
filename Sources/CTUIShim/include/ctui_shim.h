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

// シグナルハンドラから触る状態を Swift のグローバル変数へ移してはいけない。ハンドラが書いてよい
// 静的な変数は `volatile sig_atomic_t` かロックフリーなアトミック型に限られ、Swift の変数はどちらでもない。
// `nonisolated(unsafe)` は並行性検査を黙らせるだけで型は変わらず、`Atomic` は macOS 15 からしか使えない。

/// ウィンドウサイズ変更の合図を立てる。
void ctui_signal_set_window_resize(void);
/// 終了の合図を立てる。
void ctui_signal_set_termination(void);
/// 一時停止の合図を立てる。
void ctui_signal_set_suspend(void);
/// 再開の合図を立てる。
void ctui_signal_set_continue(void);

/// ウィンドウサイズ変更の合図を取り出して下ろす。
///
/// - Returns: 立っていれば 1、立っていなければ 0。
int ctui_signal_consume_window_resize(void);
/// 終了の合図を取り出して下ろす。
///
/// - Returns: 立っていれば 1、立っていなければ 0。
int ctui_signal_consume_termination(void);
/// 一時停止の合図を取り出して下ろす。
///
/// - Returns: 立っていれば 1、立っていなければ 0。
int ctui_signal_consume_suspend(void);
/// 再開の合図を取り出して下ろす。
///
/// - Returns: 立っていれば 1、立っていなければ 0。
int ctui_signal_consume_continue(void);

/// `poll(2)` の待ちを起こすための自己パイプの両端を覚える。
///
/// - Parameters:
///   - read_end: 読み取り側のファイル記述子。
///   - write_end: 書き込み側のファイル記述子。
void ctui_signal_set_wakeup_pipe(int read_end, int write_end);

/// `poll(2)` の待ちを起こすための自己パイプの読み取り側。
///
/// - Returns: 覚えていれば記述子、覚えていなければ -1。
int ctui_signal_wakeup_read_descriptor(void);

/// 自己パイプの読み取り側を待っている `poll(2)` を起こす。
///
/// シグナルハンドラから呼べる。使うのは非同期シグナル安全な `write(2)` だけ。
///
/// - Postcondition: `errno` は呼ぶ前の値のまま。
/// - See: [The Open Group Base Specifications](https://pubs.opengroup.org/onlinepubs/9799919799/) の
///   「Signal Concepts」にある Async-Signal-Safe Functions。
void ctui_signal_wake_up(void);

/// 標準エラー出力へ書き出す。
///
/// - Parameters:
///   - message: 書き出す文字列。ヌル終端。
void ctui_write_standard_error(const char *message);

#endif /* CTUI_SHIM_H */
