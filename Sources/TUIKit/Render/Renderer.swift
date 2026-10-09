/// 直前に書き出した `Buffer` と比べ、変わった `Cell` だけを端末デバイスへ書き出す型。
@MainActor
public final class Renderer {
    private let output: TerminalOutput
    private var previous: Buffer?

    /// 書き出し先を指定して `Renderer` を作る。
    ///
    /// - Parameters:
    ///   - output: 変わった `Cell` を書き出す先。
    public init(output: TerminalOutput) {
        self.output = output
    }

    /// 次回の描画を全画面再描画にする（リサイズ時や画面が壊れたとき用）。
    public func invalidate() {
        previous = nil
    }

    /// `buffer` を直前に書き出した `Buffer` と比べ、変わった `Cell` だけを書き出す。
    ///
    /// - Parameters:
    ///   - buffer: 描画したい画面内容。
    ///   - cursor: カーソルを表示する位置。`nil` ならカーソルを隠す。
    public func render(_ buffer: Buffer, cursor: Point? = nil) {
        let isFullRedraw = (previous == nil || previous?.size != buffer.size)

        var out = ANSI.beginSynchronizedUpdate
        out += ANSI.hideCursor
        out += ANSI.reset
        if isFullRedraw {
            out += ANSI.clearScreen
        }

        // 上の `ANSI.reset` を外すか、`currentStyle` の初期値を変えてはいけない。端末エミュレータの SGR と
        // `currentStyle` が食い違い、`Style.sgrSequence(transitioningFrom:)` が最初の `Cell` の SGR を省く。
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
                // `Cell.isContinuation` が `true` の `Cell` だけを描き直しても全角文字は直らない。
                // 左隣の、全角文字を持つ `Cell` から描き直す。
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
                        // この `Cell` の `Cell.character` を書き出してはいけない。直前の全角文字で端末エミュレータの
                        // カーソルはこの `Cell` の先へ進んでいるので、その行の右側の `Cell` がずれる。
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
        // `out` を分けて書き出してはいけない。`ANSI.endSynchronizedUpdate` を書き出す前に止まると、
        // 端末エミュレータは更新を保留したまま待ち続ける。
        output.write(out)
        output.flush()
    }
}
