/// 選択位置とスクロール位置を保持するリストの状態。
public final class ListState {
    /// 選択している項目の位置。
    public private(set) var selectedIndex: Int = 0
    /// 表示の先頭にある項目の位置。
    public private(set) var scrollOffset: Int = 0
    /// 一度に表示できる行数。描画時に `ListView` が更新する。
    public internal(set) var visibleRows: Int = 0

    /// 項目の総数。`ListView` の初期化時に更新される。
    public var itemCount: Int {
        didSet { clamp() }
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
        clamp()
    }

    /// 選択を上へ動かす。
    ///
    /// - Parameters:
    ///   - amount: 動かす行数。
    public func moveUp(by amount: Int = 1) {
        selectedIndex -= amount
        clamp()
    }

    /// 選択を下へ動かす。
    ///
    /// - Parameters:
    ///   - amount: 動かす行数。
    public func moveDown(by amount: Int = 1) {
        selectedIndex += amount
        clamp()
    }

    /// 先頭の項目を選択する。
    public func moveToStart() {
        selectedIndex = 0
        clamp()
    }

    /// 末尾の項目を選択する。
    public func moveToEnd() {
        selectedIndex = itemCount - 1
        clamp()
    }

    /// 上下キー・PageUp/PageDown・Home/End と縦方向のホイールを処理する。
    ///
    /// - Parameters:
    ///   - event: 端末から届いたイベント。
    /// - Returns: 選択を動かしたら `true`。
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
                    moveUp()
                    return true
                case .scrollDown:
                    moveDown()
                    return true
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

    /// 選択位置が表示範囲に入るようスクロール位置を調整する。
    ///
    /// - Postcondition: `selectedIndex` は 0 以上 `itemCount` 未満、
    ///   `scrollOffset` は `selectedIndex` が表示範囲に入る値になる。
    func clamp() {
        if itemCount <= 0 {
            selectedIndex = 0
            scrollOffset = 0
            return
        }
        selectedIndex = min(max(0, selectedIndex), itemCount - 1)

        guard visibleRows > 0 else {
            scrollOffset = 0
            return
        }
        if selectedIndex < scrollOffset {
            scrollOffset = selectedIndex
        } else if selectedIndex >= scrollOffset + visibleRows {
            scrollOffset = selectedIndex - visibleRows + 1
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
    /// - Postcondition: `state.visibleRows` が `rect` の高さに更新され、
    ///   選択位置が表示範囲に入るようスクロール位置が調整される。
    public func render(into buffer: inout Buffer, rect: Rect) {
        guard !rect.isEmpty else { return }

        state.visibleRows = rect.height
        state.clamp()

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
