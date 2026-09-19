/// 選択位置とスクロール位置を保持するリストの状態。
public final class ListState {
    /// 選択している項目の位置。
    public private(set) var selectedIndex: Int = 0
    /// 表示の先頭にある項目の位置。
    public private(set) var scrollOffset: Int = 0
    /// 直前の描画で使った矩形。描画時に `ListView` が更新する。
    public internal(set) var renderedRect: Rect = .zero
    /// ホイール 1 回で動かす行数。
    public var wheelScrollRows: Int = 2

    /// 一度に表示できる行数。
    public var visibleRows: Int { renderedRect.height }

    /// 項目の総数。`ListView` の初期化時に更新される。
    public var itemCount: Int {
        didSet {
            // 同じ値の代入で表示位置を選択へ戻してはいけない。
            // `ListView` は描画のたびに作られ、同じ項目数が入り直すので、
            // ホイールで動かした表示位置が 1 フレームで消える。
            guard itemCount != oldValue else { return }
            scrollToSelection()
        }
    }

    /// 項目数を指定して状態を作る。
    ///
    /// - Parameters:
    ///   - itemCount: 項目の総数。
    public init(itemCount: Int = 0) {
        self.itemCount = itemCount
    }

    /// 指定した位置を選択する。
    ///
    /// - Parameters:
    ///   - index: 選択する位置。範囲外の値は端へ丸められる。
    public func select(_ index: Int) {
        selectedIndex = index
        scrollToSelection()
    }

    /// 選択を上へ動かす。
    ///
    /// - Parameters:
    ///   - amount: 動かす行数。
    public func moveUp(by amount: Int = 1) {
        selectedIndex -= amount
        scrollToSelection()
    }

    /// 選択を下へ動かす。
    ///
    /// - Parameters:
    ///   - amount: 動かす行数。
    public func moveDown(by amount: Int = 1) {
        selectedIndex += amount
        scrollToSelection()
    }

    /// 先頭の項目を選択する。
    public func moveToStart() {
        selectedIndex = 0
        scrollToSelection()
    }

    /// 末尾の項目を選択する。
    public func moveToEnd() {
        selectedIndex = itemCount - 1
        scrollToSelection()
    }

    /// 表示位置だけを動かす。選択は動かさない。
    ///
    /// - Parameters:
    ///   - amount: 動かす行数。正で下、負で上。表示位置は項目の範囲へ丸められる。
    public func scroll(by amount: Int) {
        scrollOffset += amount
        clampScroll()
    }

    /// 上下キー・PageUp/PageDown・Home/End と縦方向のホイールを処理する。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: 選択または表示位置を動かしたら `true`。
    /// - Note: ホイールは選択ではなく表示位置を `wheelScrollRows` 行動かす。
    ///   `renderedRect` の外で起きたホイールは処理しない。
    @discardableResult
    public func handle(_ event: InputEvent) -> Bool {
        guard case .key(let keyEvent) = event else {
            if case .mouse(let mouseEvent) = event {
                // 1 列の選択リストなので、扱うのは縦方向のみ。横スクロールは
                // トラックパッドの斜めの動きで混ざってくるが、このビューの
                // 責務ではないので false を返して親に委ねる。
                //
                // `default` を置かずに全ケースを列挙している。`MouseAction` が
                // 増えたときにコンパイルエラーとなり、この場で方針を決めることを
                // 強制するため。
                switch mouseEvent.action {
                case .scrollUp:
                    return scrollByWheel(at: mouseEvent.position, rows: -wheelScrollRows)
                case .scrollDown:
                    return scrollByWheel(at: mouseEvent.position, rows: wheelScrollRows)
                case .scrollLeft, .scrollRight:
                    return false
                case .press, .release, .drag:
                    return false
                }
            }
            return false
        }

        switch keyEvent.key {
        case .up:
            moveUp()
        case .down:
            moveDown()
        case .pageUp:
            moveUp(by: max(1, visibleRows))
        case .pageDown:
            moveDown(by: max(1, visibleRows))
        case .home:
            moveToStart()
        case .end:
            moveToEnd()
        case .character("k"):
            moveUp()
        case .character("j"):
            moveDown()
        default:
            return false
        }
        return true
    }

    /// 矩形の中で起きたホイールとして表示位置を動かす。
    ///
    /// - Parameters:
    ///   - position: ホイールが起きた位置。
    ///   - rows: 動かす行数。正で下、負で上。
    /// - Returns: 矩形の中で起きていたら `true`。
    private func scrollByWheel(at position: Point, rows: Int) -> Bool {
        guard renderedRect.contains(position) else { return false }
        scroll(by: rows)
        return true
    }

    /// 選択位置が表示範囲に入るよう表示位置を動かす。
    ///
    /// - Postcondition: `selectedIndex` は 0 以上 `itemCount` 未満、
    ///   `scrollOffset` は `selectedIndex` が表示範囲に入る値になる。
    func scrollToSelection() {
        if itemCount <= 0 {
            selectedIndex = 0
            scrollOffset = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), itemCount - 1)

        if visibleRows > 0 {
            if selectedIndex < scrollOffset {
                scrollOffset = selectedIndex
            } else if selectedIndex >= scrollOffset + visibleRows {
                scrollOffset = selectedIndex - visibleRows + 1
            }
        }
        clampScroll()
    }

    /// 表示位置を項目の範囲へ収める。選択は追いかけない。
    ///
    /// - Postcondition: `scrollOffset` は 0 以上 `itemCount - visibleRows` 以下になる。
    func clampScroll() {
        guard itemCount > 0, visibleRows > 0 else {
            scrollOffset = 0
            return
        }
        scrollOffset = min(max(0, scrollOffset), max(0, itemCount - visibleRows))
    }
}

/// 選択可能なリスト。
public struct ListView: View {
    /// 各行に表示する文字列。
    public var items: [String]
    /// 選択位置とスクロール位置を持つ状態。
    public var state: ListState
    /// 非選択行のスタイル。
    public var style: Style
    /// 選択行のスタイル。
    public var selectedStyle: Style
    /// 選択行の先頭に付ける印。
    public var selectionMarker: String
    /// 非選択行の先頭に入れる字下げ。既定では `selectionMarker` と同じ幅の空白。
    public var marginMarker: String?

    /// 項目と状態を指定してリストを作る。
    ///
    /// - Parameters:
    ///   - items: 各行に表示する文字列。
    ///   - state: 選択位置とスクロール位置を持つ状態。
    ///   - style: 非選択行のスタイル。
    ///   - selectedStyle: 選択行のスタイル。
    ///   - selectionMarker: 選択行の先頭に付ける印。
    ///   - marginMarker: 非選択行の先頭に入れる字下げ。`nil` なら印と同じ幅の空白。
    /// - Postcondition: `state.itemCount` が `items` の個数に更新される。
    public init(
        items: [String],
        state: ListState,
        style: Style = .plain,
        selectedStyle: Style = Style(attributes: .reverse),
        selectionMarker: String = "> ",
        marginMarker: String? = nil
    ) {
        self.items = items
        self.state = state
        self.style = style
        self.selectedStyle = selectedStyle
        self.selectionMarker = selectionMarker
        self.marginMarker = marginMarker
        state.itemCount = items.count
    }

    /// 両方向に伸びる。
    public var layoutTraits: LayoutTraits { .flexible }

    /// すべての項目を並べたときに必要なサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 親から提案された領域の大きさ。
    /// - Returns: 最も長い項目の幅に印の幅を足した幅と、項目数から決まるサイズ。
    public func sizeThatFits(_ proposal: Size) -> Size {
        let width = items.reduce(0) { max($0, DisplayWidth.width(of: $1)) }
            + DisplayWidth.width(of: selectionMarker)
        return Size(
            width: min(width, proposal.width),
            height: min(items.count, proposal.height)
        )
    }

    /// 表示範囲の項目を上から並べて描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。
    ///   - rect: 描画する矩形。
    /// - Postcondition: `state.renderedRect` が `rect` に更新され、
    ///   スクロール位置が項目の範囲へ収められる。
    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }

        // 描画のたびに選択へ戻すと、ホイールで動かした表示位置が元に戻る。
        // 表示できる行数が変わったときだけ選択を追いかける。
        let rowsChanged = state.visibleRows != rect.height
        state.renderedRect = rect
        if rowsChanged {
            state.scrollToSelection()
        } else {
            state.clampScroll()
        }

        let margin = marginMarker ?? String(
            repeating: " ",
            count: DisplayWidth.width(of: selectionMarker)
        )

        for row in 0..<rect.height {
            let index = state.scrollOffset + row
            guard index < items.count else { break }

            let isSelected = (index == state.selectedIndex)
            let rowStyle = isSelected ? selectedStyle : style
            let prefix = isSelected ? selectionMarker : margin
            // 幅で切り詰める前に展開しないと、タブの分だけ桁数の計算がずれる。
            let line = TabExpansion.expand(prefix + items[index])
            let y = rect.minY + row

            // 選択行は行末まで塗って反転が途切れないようにする。
            if isSelected {
                buffer.fill(
                    Rect(x: rect.minX, y: y, width: rect.width, height: 1),
                    with: Cell(character: " ", style: rowStyle)
                )
            }
            buffer.write(
                DisplayWidth.truncate(line, to: rect.width),
                at: Point(x: rect.minX, y: y),
                style: rowStyle,
                clippedTo: rect
            )
        }
    }
}
