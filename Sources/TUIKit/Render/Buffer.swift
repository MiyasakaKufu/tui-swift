/// 画面 1 枚分のセル配列。描画はすべてこのバッファに対して行う。
public struct Buffer: Hashable, Sendable {
    /// バッファの大きさ。
    public private(set) var size: Size
    /// East Asian Width が Ambiguous の文字を何桁のセルとして置くか。
    public let ambiguousWidth: DisplayWidth.AmbiguousWidth
    private var cells: [Cell]

    /// 指定したサイズのバッファを作る。
    ///
    /// - Parameters:
    ///   - size: バッファの大きさ。
    ///   - cell: 全体を埋めるセル。
    ///   - ambiguousWidth: 曖昧幅の文字の扱い。端末の設定に合わせる。
    public init(
        size: Size,
        filledWith cell: Cell = .empty,
        ambiguousWidth: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) {
        self.size = size
        self.ambiguousWidth = ambiguousWidth
        self.cells = [Cell](repeating: cell, count: size.width * size.height)
    }

    /// バッファ全体を覆う矩形。
    public var bounds: Rect {
        Rect(x: 0, y: 0, width: size.width, height: size.height)
    }

    /// 指定した桁・行のセルへアクセスする。
    ///
    /// - Parameters:
    ///   - x: 桁。左端が 0。
    ///   - y: 行。上端が 0。
    /// - Postcondition: 全角文字が占める 2 桁のうち片側だけを書き換えたとき、対にならなくなった
    ///   残りの側は空白になる。
    /// - Note: 範囲外の読み取りは `.empty` を返し、範囲外への書き込みは無視される。
    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard x >= 0, y >= 0, x < size.width, y < size.height else { return .empty }
            return cells[y * size.width + x]
        }
        set {
            guard x >= 0, y >= 0, x < size.width, y < size.height else { return }
            // この 2 つの分岐を外して代入だけに戻してはいけない。全角文字の片側だけが残ると、
            // 端末はそれを 2 桁で描くので、その行の以降の桁がずれる。
            if !newValue.isContinuation, x > 0, cells[y * size.width + x].isContinuation {
                blankCell(atColumn: x - 1, row: y)
            }
            if x + 1 < size.width,
               cells[y * size.width + x + 1].isContinuation,
               !coversNextColumn(newValue) {
                blankCell(atColumn: x + 1, row: y)
            }
            cells[y * size.width + x] = newValue
        }
    }

    /// 右隣の桁まで占めるセルか。
    ///
    /// - Parameters:
    ///   - cell: 調べるセル。
    /// - Returns: 表示幅が 2 桁以上なら `true`。
    private func coversNextColumn(_ cell: Cell) -> Bool {
        DisplayWidth.width(of: cell.character, ambiguous: ambiguousWidth) > 1
    }

    /// 1 桁を、スタイルを保ったまま空白へ戻す。
    ///
    /// - Parameters:
    ///   - x: 桁。左端が 0。
    ///   - y: 行。上端が 0。
    /// - Precondition: `x` と `y` がバッファの範囲内にある。
    private mutating func blankCell(atColumn x: Int, row y: Int) {
        let index = y * size.width + x
        cells[index] = Cell(character: " ", style: cells[index].style)
    }

    /// サイズを変更し、内容を初期化する。
    ///
    /// - Parameters:
    ///   - newSize: 変更後の大きさ。
    ///   - cell: 全体を埋めるセル。
    public mutating func resize(to newSize: Size, filledWith cell: Cell = .empty) {
        size = newSize
        cells = [Cell](repeating: cell, count: newSize.width * newSize.height)
    }

    /// 全体を空白で塗りつぶす。
    ///
    /// - Parameters:
    ///   - style: 空白に付けるスタイル。
    public mutating func clear(with style: Style = .plain) {
        let cell = Cell(character: " ", style: style)
        for index in cells.indices {
            cells[index] = cell
        }
    }

    /// 矩形領域を塗りつぶす。
    ///
    /// - Parameters:
    ///   - rect: 塗りつぶす矩形。バッファの外へはみ出した部分は無視される。
    ///   - cell: 埋めるセル。
    public mutating func fill(_ rect: Rect, with cell: Cell) {
        let region = rect.intersection(bounds)
        guard !region.isEmpty else { return }
        for y in region.minY..<region.maxY {
            for x in region.minX..<region.maxX {
                self[x, y] = cell
            }
        }
    }

    /// 矩形領域の背景スタイルだけを差し替える。
    ///
    /// - Parameters:
    ///   - rect: 差し替える矩形。バッファの外へはみ出した部分は無視される。
    ///   - style: 塗るスタイル。
    public mutating func fill(_ rect: Rect, style: Style) {
        fill(rect, with: Cell(character: " ", style: style))
    }

    /// 矩形領域を 1 文字の繰り返しで埋める。
    ///
    /// - Parameters:
    ///   - rect: 埋める矩形。バッファの外へはみ出した部分は無視される。
    ///   - character: 繰り返す文字。表示幅が 0 の文字は繰り返せないため、領域全体を空白で埋める。
    ///   - style: 文字に付けるスタイル。
    /// - Postcondition: 領域の幅が文字の表示幅で割り切れないとき、行末に残った桁は空白になる。
    public mutating func fill(_ rect: Rect, repeating character: Character, style: Style = .plain) {
        let region = rect.intersection(bounds)
        guard !region.isEmpty else { return }

        let characterWidth = DisplayWidth.width(of: character, ambiguous: ambiguousWidth)
        guard characterWidth >= 1 else {
            fill(region, with: Cell(character: " ", style: style))
            return
        }
        guard characterWidth > 1 else {
            fill(region, with: Cell(character: character, style: style))
            return
        }

        let head = Cell(character: character, style: style)
        let continuation = Cell(character: " ", style: style, isContinuation: true)
        let blank = Cell(character: " ", style: style)

        for y in region.minY..<region.maxY {
            var x = region.minX
            while x + characterWidth <= region.maxX {
                self[x, y] = head
                for offset in 1..<characterWidth {
                    self[x + offset, y] = continuation
                }
                x += characterWidth
            }
            // 端末は全角文字を半分だけ描けない。半端に残った桁を文字で埋めてはいけない。
            while x < region.maxX {
                self[x, y] = blank
                x += 1
            }
        }
    }

    /// 1 行分の文字列を描画する。
    ///
    /// - Parameters:
    ///   - text: 描画する文字列。最初の改行以降は無視される。
    ///   - position: 開始位置。
    ///   - style: 文字のスタイル。
    ///   - clip: 描画を制限する矩形。省略時はバッファ全体。
    /// - Returns: 進んだ桁数（クリップされた分も含む）。
    /// - Postcondition: 領域の端に半分だけかかる全角文字は、空白に置き換わる。
    /// - Note: タブなどの幅を持たない制御文字は描画されない。タブを表示したい場合は、
    ///   呼び出す前に `TabExpansion.expand(_:tabSize:)` で空白へ展開しておく。
    @discardableResult
    public mutating func write(
        _ text: String,
        at position: Point,
        style: Style = .plain,
        clippedTo clip: Rect? = nil
    ) -> Int {
        let region = (clip ?? bounds).intersection(bounds)
        guard !region.isEmpty else { return 0 }

        let y = position.y
        guard y >= region.minY, y < region.maxY else { return 0 }

        var x = position.x
        for character in text {
            if character.isNewline { break }

            let characterWidth = DisplayWidth.width(of: character, ambiguous: ambiguousWidth)
            if characterWidth == 0 { continue }
            if x >= region.maxX { break }

            if x + characterWidth <= region.minX {
                x += characterWidth
                continue
            }

            // 端末は全角文字を半分だけ描けない。領域の端に半分だけかかる文字を、
            // その文字で埋めてはいけない。
            if x >= region.minX {
                if characterWidth == 2 {
                    if x + 1 < region.maxX {
                        self[x, y] = Cell(character: character, style: style)
                        self[x + 1, y] = Cell(character: " ", style: style, isContinuation: true)
                    } else {
                        self[x, y] = Cell(character: " ", style: style)
                    }
                } else {
                    self[x, y] = Cell(character: character, style: style)
                }
            } else {
                self[region.minX, y] = Cell(character: " ", style: style)
            }

            x += characterWidth
        }
        return x - position.x
    }

    /// 複数行の文字列を、`rect` の中に指定の揃えで描画する。
    ///
    /// - Parameters:
    ///   - lines: 各行の文字列。`rect` の高さに収まらない行は描画されない。
    ///   - rect: 描画する矩形。
    ///   - style: 文字のスタイル。
    ///   - alignment: 行の水平方向の揃え。
    /// - Note: タブなどの幅を持たない制御文字は描画されない。タブを表示したい場合は、
    ///   呼び出す前に `TabExpansion.expand(_:tabSize:)` で空白へ展開しておく。
    public mutating func write(
        lines: [String],
        in rect: Rect,
        style: Style = .plain,
        alignment: HorizontalAlignment = .leading
    ) {
        let region = rect.intersection(bounds)
        guard !region.isEmpty else { return }

        for (offset, line) in lines.enumerated() {
            let y = rect.minY + offset
            if y >= region.maxY { break }
            if y < region.minY { continue }
            let lineWidth = DisplayWidth.width(of: line, ambiguous: ambiguousWidth)
            let x = rect.minX + alignment.offset(content: lineWidth, available: rect.width)
            write(line, at: Point(x: x, y: y), style: style, clippedTo: region)
        }
    }

    /// デバッグ・テスト用に 1 行を文字列として取り出す。
    ///
    /// - Parameters:
    ///   - y: 取り出す行。上端が 0。
    /// - Returns: その行の文字を並べた文字列。継続セルの分は含まない。
    ///   範囲外の行を指定すると空文字列。
    public func text(ofRow y: Int) -> String {
        guard y >= 0, y < size.height else { return "" }
        var result = ""
        for x in 0..<size.width {
            let cell = self[x, y]
            if cell.isContinuation { continue }
            result.append(cell.character)
        }
        return result
    }

    /// デバッグ・テスト用に全体を文字列化する。
    ///
    /// - Returns: 各行を改行で連ねた文字列。
    public func debugText() -> String {
        (0..<size.height).map { text(ofRow: $0) }.joined(separator: "\n")
    }
}
