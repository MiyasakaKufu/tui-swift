/// 直前のフレームとの差分だけを端末へ書き出すレンダラ。
public final class Renderer {
    private let output: TerminalOutput
    private var previous: Buffer?

    /// 書き出し先を指定してレンダラを作る。
    ///
    /// - Parameters:
    ///   - output: 差分を書き出す先。
    public init(output: TerminalOutput) {
        self.output = output
    }

    /// 次回の描画を全画面再描画にする（リサイズ時や画面が壊れたとき用）。
    public func invalidate() {
        previous = nil
    }

    /// バッファを描画し、直前のフレームとの差分だけを書き出す。
    ///
    /// - Parameters:
    ///   - buffer: 描画したい画面内容。
    ///   - cursor: カーソルを表示する位置。`nil` ならカーソルを隠す。
    /// - Note: 1 フレーム分を同期出力（`ANSI.beginSynchronizedUpdate`）で囲むので、
    ///   対応する端末では描画の途中が見えない。
    public func render(_ buffer: Buffer, cursor: Point? = nil) {
        let isFullRedraw = (previous == nil || previous?.size != buffer.size)

        var out = ANSI.beginSynchronizedUpdate
        out += ANSI.hideCursor
        out += ANSI.reset
        if isFullRedraw {
            out += ANSI.clearScreen
        }

        // フレーム冒頭で SGR を全解除しているので、現在のスタイルは既定値。
        var currentStyle = Style.plain
        var cursorRow = -1
        var cursorColumn = -1

        let width = buffer.size.width
        let height = buffer.size.height

        for y in 0..<height {
            var dirty = [Bool](repeating: isFullRedraw, count: width)
            if !isFullRedraw, let previousBuffer = previous {
                for x in 0..<width {
                    dirty[x] = buffer[x, y] != previousBuffer[x, y]
                }
                // 継続セルだけを描き直しても全角文字は直らない。基底セルから描き直す。
                for x in 1..<max(1, width) where dirty[x] && buffer[x, y].isContinuation {
                    dirty[x - 1] = true
                }
            }

            var x = 0
            while x < width {
                guard dirty[x] else {
                    x += 1
                    continue
                }

                var start = x
                if buffer[start, y].isContinuation && start > 0 {
                    start -= 1
                }

                if cursorRow != y || cursorColumn != start {
                    out += ANSI.moveCursor(row: y + 1, column: start + 1)
                }

                var column = start
                while column < width {
                    let cell = buffer[column, y]
                    if cell.isContinuation {
                        // 直前の全角文字が既にこの桁を埋めている。
                        column += 1
                        continue
                    }
                    if column > start && !dirty[column] { break }

                    let sequence = cell.style.sgrSequence(transitioningFrom: currentStyle)
                    if !sequence.isEmpty {
                        out += sequence
                        currentStyle = cell.style
                    }
                    out.append(cell.character)
                    column += 1
                }

                cursorRow = y
                cursorColumn = column
                x = max(column, x + 1)
            }
        }

        out += ANSI.reset
        if let cursor {
            out += ANSI.moveCursor(row: cursor.y + 1, column: cursor.x + 1)
            out += ANSI.showCursor
        }

        out += ANSI.endSynchronizedUpdate

        previous = buffer
        // フレームを分けて書き出してはいけない。閉じる前に止まると、端末は更新を
        // 保留したまま待ち続ける。
        output.write(out)
        output.flush()
    }
}
