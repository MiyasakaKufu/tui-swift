#ifndef CTUI_SHIM_H
#define CTUI_SHIM_H

/// 端末のウィンドウサイズを取得する。
///
/// Swift から C の可変長引数関数 `ioctl` を直接呼ぶことはできないため、
/// 薄いシムを用意している。成功時は 0、失敗時は -1 を返す。
int ctui_terminal_size(int fd, int *columns, int *rows);

#endif /* CTUI_SHIM_H */
