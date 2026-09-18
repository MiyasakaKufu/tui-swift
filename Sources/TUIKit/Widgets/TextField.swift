/// 1 行のテキスト入力の状態。
public final class TextFieldState {
    private var characters: [Character]
    /// カーソルの文字インデックス（0 〜 文字数）。
    public private(set) var cursor: Int

    public init(text: String = "") {
        self.characters = Array(text)
        self.cursor = characters.count
    }

    public var text: String {
        String(characters)
    }

    public var isEmpty: Bool { characters.isEmpty }

    /// カーソル位置までの表示幅。
    public var cursorColumn: Int {
        DisplayWidth.width(of: String(characters.prefix(cursor)))
    }

    public func setText(_ text: String) {
        characters = Array(text)
        cursor = characters.count
    }

    public func insert(_ character: Character) {
        characters.insert(character, at: cursor)
        cursor += 1
    }

    public func insert(contentsOf text: String) {
        for character in text where character != "\n" {
            insert(character)
        }
    }

    @discardableResult
    public func deleteBackward() -> Bool {
        guard cursor > 0 else { return false }
        characters.remove(at: cursor - 1)
        cursor -= 1
        return true
    }

    @discardableResult
    public func deleteForward() -> Bool {
        guard cursor < characters.count else { return false }
        characters.remove(at: cursor)
        return true
    }

    public func deleteToStart() {
        characters.removeFirst(cursor)
        cursor = 0
    }

    public func moveLeft() {
        cursor = max(0, cursor - 1)
    }

    public func moveRight() {
        cursor = min(characters.count, cursor + 1)
    }

    public func moveToStart() {
        cursor = 0
    }

    public func moveToEnd() {
        cursor = characters.count
    }

    /// 文字入力・カーソル移動・削除を処理する。処理したら `true`。
    @discardableResult
    public func handle(_ event: InputEvent) -> Bool {
        switch event {
        case .paste(let text):
            insert(contentsOf: text)
            return true
        case .key(let keyEvent):
            return handle(keyEvent)
        default:
            return false
        }
    }

    private func handle(_ event: KeyEvent) -> Bool {
        if event.modifiers.contains(.control) {
            switch event.key {
            case .character("a"):
                moveToStart()
            case .character("e"):
                moveToEnd()
            case .character("u"):
                deleteToStart()
            case .character("h"):
                deleteBackward()
            case .character("k"):
                characters.removeLast(characters.count - cursor)
            default:
                return false
            }
            return true
        }

        switch event.key {
        case .character(let character):
            insert(character)
        case .backspace:
            deleteBackward()
        case .delete:
            deleteForward()
        case .left:
            moveLeft()
        case .right:
            moveRight()
        case .home:
            moveToStart()
        case .end:
            moveToEnd()
        default:
            return false
        }
        return true
    }
}

/// 1 行のテキスト入力欄。
public struct TextField: View {
    public var state: TextFieldState
    public var placeholder: String
    public var style: Style
    public var placeholderStyle: Style
    /// カーソル位置を反転表示する（アプリ側で端末カーソルを出す場合は `false`）。
    public var showsCursor: Bool

    public init(
        state: TextFieldState,
        placeholder: String = "",
        style: Style = .plain,
        placeholderStyle: Style = Style(foreground: .brightBlack),
        showsCursor: Bool = true
    ) {
        self.state = state
        self.placeholder = placeholder
        self.style = style
        self.placeholderStyle = placeholderStyle
        self.showsCursor = showsCursor
    }

    public var layoutTraits: LayoutTraits { LayoutTraits(horizontalFlex: 1, verticalFlex: 0) }

    public func sizeThatFits(_ proposal: Size) -> Size {
        Size(width: proposal.width, height: min(1, proposal.height))
    }

    /// 与えられた幅のとき、先頭何桁分をスクロールして隠すか。
    public func scrollOffset(forWidth width: Int) -> Int {
        guard width > 0 else { return 0 }
        let column = state.cursorColumn
        if column >= width {
            return column - width + 1
        }
        return 0
    }

    public func render(into buffer: inout Buffer, rect: Rect) {
        guard rect.width > 0, rect.height > 0 else { return }
        let row = Rect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)
        buffer.fill(row, with: Cell(character: " ", style: style))

        if state.isEmpty && !placeholder.isEmpty {
            buffer.write(
                DisplayWidth.truncate(placeholder, to: rect.width),
                at: Point(x: rect.minX, y: rect.minY),
                style: placeholderStyle,
                clippedTo: row
            )
            // 空でもどこに入力されるか分かるよう、プレースホルダーの先頭セルに
            // カーソルを重ねる。表示幅は変わらない。
            drawCursor(into: &buffer, at: Point(x: rect.minX, y: rect.minY), in: rect)
            return
        }

        let offset = scrollOffset(forWidth: rect.width)
        buffer.write(
            state.text,
            at: Point(x: rect.minX - offset, y: rect.minY),
            style: style,
            clippedTo: row
        )

        drawCursor(
            into: &buffer,
            at: Point(x: rect.minX + state.cursorColumn - offset, y: rect.minY),
            in: rect
        )
    }

    /// カーソル位置のセルを反転させる。
    private func drawCursor(into buffer: inout Buffer, at point: Point, in rect: Rect) {
        guard showsCursor, point.x >= rect.minX, point.x < rect.maxX else { return }
        var cell = buffer[point.x, point.y]
        cell.style = cell.style.adding(.reverse)
        cell.isContinuation = false
        buffer[point.x, point.y] = cell
    }
}
