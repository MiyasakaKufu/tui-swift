#ifndef CTUI_TEST_SUPPORT_H
#define CTUI_TEST_SUPPORT_H

/// 疑似端末（pty）を開き、master と slave の記述子を返す。
///
/// - Parameters:
///   - master: master の記述子の書き込み先。
///   - slave: slave の記述子の書き込み先。
/// - Returns: 成功なら 0、失敗なら -1。
/// - Postcondition: 失敗した場合は記述子に触れない。
int ctui_test_open_pty(int *master, int *slave);

/// 端末のウィンドウサイズを設定する。
///
/// - Parameters:
///   - fd: 設定するファイル記述子。
///   - columns: 桁数。
///   - rows: 行数。
/// - Returns: 成功なら 0、失敗なら -1。
int ctui_test_set_terminal_size(int fd, int columns, int rows);

#endif /* CTUI_TEST_SUPPORT_H */
