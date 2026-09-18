/// 1 行のテキスト入力の状態。
///
/// 内容は書記素クラスタ（Swift の `Character`）単位で持つ。端末からは 🇯🇵 や
/// 👨‍👩‍👧 が Unicode スカラーごとに届く（パーサがスカラーごとにキーイベントを出す）
/// ため、変更のたびに区切り直して 1 文字として扱えるようにする。
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
        replace(cursor..<cursor, with: String(character))
    }

    public func insert(contentsOf text: String) {
        let inserted = String(text.filter { $0 != "\n" })
        guard !inserted.isEmpty else { return }
        replace(cursor..<cursor, with: inserted)
    }

    @discardableResult
    public func deleteBackward() -> Bool {
        guard cursor > 0 else { return false }
        replace((cursor - 1)..<cursor, with: "")
        return true
    }

    @discardableResult
    public func deleteForward() -> Bool {
        guard cursor < characters.count else { return false }
        replace(cursor..<(cursor + 1), with: "")
        return true
    }

    public func deleteToStart() {
        replace(0..<cursor, with: "")
    }

    public func deleteToEnd() {
        replace(cursor..<characters.count, with: "")
    }

    /// `range` の文字を `text` に置き換え、書記素クラスタを区切り直す。
    ///
    /// カーソルは `text` の末尾に置く。挿入した文字が前後と 1 つの書記素クラスタに
    /// 結合した場合は、そのクラスタの後ろに置く。
    private func replace(_ range: Range<Int>, with text: String) {
        let head = String(characters[..<range.lowerBound]) + text
        let tail = String(characters[range.upperBound...])
        characters = Array(head + tail)
        cursor = TextFieldState.characterIndex(in: characters, afterUTF8Length: head.utf8.count)
    }

    /// 先頭から数えて UTF-8 で `length` バイトの位置にあたる文字インデックス。
    ///
    /// その位置が書記素クラスタの内部に来る場合は、そのクラスタの後ろを返す。
    private static func characterIndex(in characters: [Character], afterUTF8Length length: Int) -> Int {
        var consumed = 0
        var index = 0
        while index < characters.count && consumed < length {
            consumed += String(characters[index]).utf8.count
            index += 1
        }
        return index
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
                deleteToEnd()
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

        if state.isEmpty && !placeholder.isEmpty {
            buffer.fill(row, with: Cell(character: " ", style: style))
            buffer.write(
                DisplayWidth.truncate(placeholder, to: rect.width),
                at: Point(x: rect.minX, y: rect.minY),
                style: placeholderStyle,
                clippedTo: row
            )
            return
        }

        let offset = scrollOffset(forWidth: rect.width)
        buffer.fill(row, with: Cell(character: " ", style: style))
        buffer.write(
            state.text,
            at: Point(x: rect.minX - offset, y: rect.minY),
            style: style,
            clippedTo: row
        )

        if showsCursor {
            let x = rect.minX + state.cursorColumn - offset
            if x >= rect.minX && x < rect.maxX {
                var cell = buffer[x, rect.minY]
                cell.style = cell.style.adding(.reverse)
                cell.isContinuation = false
                buffer[x, rect.minY] = cell
            }
        }
    }
}
