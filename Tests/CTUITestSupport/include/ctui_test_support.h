#ifndef CTUI_TEST_SUPPORT_H
#define CTUI_TEST_SUPPORT_H

/// 疑似端末（pty）を開き、master と slave の記述子を返す。
///
/// 成功時は 0、失敗時は -1 を返す。失敗した場合は記述子に触れない。
int ctui_test_open_pty(int *master, int *slave);

/// 端末のウィンドウサイズを設定する。
///
/// 成功時は 0、失敗時は -1 を返す。
int ctui_test_set_terminal_size(int fd, int columns, int rows);

#endif /* CTUI_TEST_SUPPORT_H */
