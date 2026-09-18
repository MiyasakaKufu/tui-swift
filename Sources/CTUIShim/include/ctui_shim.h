#ifndef CTUI_SHIM_H
#define CTUI_SHIM_H

/// 端末のウィンドウサイズを取得する。
///
/// Swift から C の可変長引数関数 `ioctl` を直接呼ぶことはできないため、
/// 薄いシムを用意している。成功時は 0、失敗時は -1 を返す。
int ctui_terminal_size(int fd, int *columns, int *rows);

/// 端末のウィンドウサイズを設定する。
///
/// 疑似端末（pty）のマスタ側に対して使い、スレーブ側で動くプログラムから見える
/// サイズを変える。成功時は 0、失敗時は -1 を返す。
int ctui_set_terminal_size(int fd, int columns, int rows);

#endif /* CTUI_SHIM_H */
