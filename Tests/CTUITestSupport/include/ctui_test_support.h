#ifndef CTUI_TEST_SUPPORT_H
#define CTUI_TEST_SUPPORT_H

/// POSIX の pseudo-terminal（pty）を開き、manager device と subsidiary device の記述子を `master`・`slave` に書き込む。
///
/// - Parameters:
///   - master: manager device の記述子の書き込み先。
///   - slave: subsidiary device の記述子の書き込み先。
/// - Returns: 成功なら 0、失敗なら -1。
/// - Postcondition: 失敗した場合は記述子に触れない。
int ctui_test_open_pty(int *master, int *slave);

/// 端末デバイスのウィンドウサイズを設定する。
///
/// - Parameters:
///   - fd: pseudo-terminal の manager device か subsidiary device のファイル記述子。どちらを渡しても、
///     subsidiary device（端末デバイス）のウィンドウサイズが変わる。
///   - columns: 横方向の `Cell` の数（`ws_col`）。
///   - rows: 行数。
/// - Returns: 成功なら 0、失敗なら -1。
int ctui_test_set_terminal_size(int fd, int columns, int rows);

#endif /* CTUI_TEST_SUPPORT_H */
