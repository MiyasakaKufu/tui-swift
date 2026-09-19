/// 画面 1 枚分のセル配列。描画はすべてこのバッファに対して行う。
public struct Buffer: Hashable, Sendable {
    public private(set) var size: Size
    private var cells: [Cell]

    public init(size: Size, filledWith cell: Cell = .empty) {
        self.size = size
        self.cells = [Cell](repeating: cell, count: size.width * size.height)
    }

    /// バッファ全体を覆う矩形。
    public var bounds: Rect {
        Rect(x: 0, y: 0, width: size.width, height: size.height)
    }

    /// 範囲外の読み取りは `.empty`、範囲外への書き込みは無視される。
    public subscript(x: Int, y: Int) -> Cell {
        get {
            guard x >= 0, y >= 0, x < size.width, y < size.height else { return .empty }
            return cells[y * size.width + x]
        }
        set {
            guard x >= 0, y >= 0, x < size.width, y < size.height else { return }
            cells[y * size.width + x] = newValue
        }
    }

    /// サイズを変更し、内容を初期化する。
    public mutating func resize(to newSize: Size, filledWith cell: Cell = .empty) {
        size = newSize
        cells = [Cell](repeating: cell, count: newSize.width * newSize.height)
    }

    /// 全体を空白で塗りつぶす。
    public mutating func clear(with style: Style = .plain) {
        let cell = Cell(character: " ", style: style)
        for index in cells.indices {
            cells[index] = cell
        }
    }

    /// 矩形領域を塗りつぶす。
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
    public mutating func fill(_ rect: Rect, style: Style) {
        fill(rect, with: Cell(character: " ", style: style))
    }

    /// 1 行分の文字列を描画する。
    ///
    /// - Parameters:
    ///   - text: 描画する文字列。最初の改行以降は無視される。
    ///   - position: 開始位置。
    ///   - style: 文字のスタイル。
    ///   - clip: 描画を制限する矩形。省略時はバッファ全体。
    /// - Returns: 進んだ桁数（クリップされた分も含む）。
    ///
    /// タブなどの幅を持たない制御文字は描画されない。タブを表示したい場合は、
    /// 呼び出す前に `TabExpansion.expand(_:tabSize:)` で空白へ展開しておく。
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

            let characterWidth = DisplayWidth.width(of: character)
            if characterWidth == 0 { continue }
            if x >= region.maxX { break }

            if x + characterWidth <= region.minX {
                // 完全に左側へはみ出している。
                x += characterWidth
                continue
            }

            if x >= region.minX {
                if characterWidth == 2 {
                    if x + 1 < region.maxX {
                        self[x, y] = Cell(character: character, style: style)
                        self[x + 1, y] = Cell(character: " ", style: style, isContinuation: true)
                    } else {
                        // 右端に半分しか入らない全角文字は空白で埋める。
                        self[x, y] = Cell(character: " ", style: style)
                    }
                } else {
                    self[x, y] = Cell(character: character, style: style)
                }
            } else {
                // 左端をまたぐ全角文字。右半分だけを空白で埋める。
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
    ///
    /// タブなどの幅を持たない制御文字は描画されない。タブを表示したい場合は、
    /// 呼び出す前に `TabExpansion.expand(_:tabSize:)` で空白へ展開しておく。
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
            let lineWidth = DisplayWidth.width(of: line)
            let x = rect.minX + alignment.offset(content: lineWidth, available: rect.width)
            write(line, at: Point(x: x, y: y), style: style, clippedTo: region)
        }
    }

    /// デバッグ・テスト用に 1 行を文字列として取り出す（継続セルは除く）。
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
    public func debugText() -> String {
        (0..<size.height).map { text(ofRow: $0) }.joined(separator: "\n")
    }
}
