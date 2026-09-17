/// 選択位置とスクロール位置を保持するリストの状態。
///
/// ビューは値型なので、状態はこのクラスで保持し、イベント処理もここで行う。
public final class ListState {
    public private(set) var selectedIndex: Int = 0
    public private(set) var scrollOffset: Int = 0
    /// 一度に表示できる行数。描画時に `ListView` が更新する。
    public internal(set) var visibleRows: Int = 0

    public var itemCount: Int {
        didSet { clamp() }
    }

    public init(itemCount: Int = 0) {
        self.itemCount = itemCount
    }

    public func select(_ index: Int) {
        selectedIndex = index
        clamp()
    }

    public func moveUp(by amount: Int = 1) {
        selectedIndex -= amount
        clamp()
    }

    public func moveDown(by amount: Int = 1) {
        selectedIndex += amount
        clamp()
    }

    public func moveToStart() {
        selectedIndex = 0
        clamp()
    }

    public func moveToEnd() {
        selectedIndex = itemCount - 1
        clamp()
    }

    /// 上下キー・PageUp/PageDown・Home/End を処理する。処理したら `true`。
    @discardableResult
    public func handle(_ event: InputEvent) -> Bool {
        guard case .key(let keyEvent) = event else {
            if case .mouse(let mouseEvent) = event {
                switch mouseEvent.action {
                case .scrollUp:
                    moveUp()
                    return true
                case .scrollDown:
                    moveDown()
                    return true
                default:
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
    public var items: [String]
    public var state: ListState
    public var style: Style
    public var selectedStyle: Style
    /// 選択行の先頭に付ける印。
    public var selectionMarker: String
    /// 非選択行の先頭に入れる字下げ。既定では `selectionMarker` と同じ幅の空白。
    public var marginMarker: String?

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

    public var layoutTraits: LayoutTraits { .flexible }

    public func sizeThatFits(_ proposal: Size) -> Size {
        let width = items.reduce(0) { max($0, DisplayWidth.width(of: $1)) }
            + DisplayWidth.width(of: selectionMarker)
        return Size(
            width: min(width, proposal.width),
            height: min(items.count, proposal.height)
        )
    }

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
            let line = prefix + items[index]
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
