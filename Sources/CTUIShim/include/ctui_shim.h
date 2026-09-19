#ifndef CTUI_SHIM_H
#define CTUI_SHIM_H

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

#endif /* CTUI_SHIM_H */
