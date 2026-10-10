/// 1 行のテキスト入力（`TextField`）が使うクラス。
///
/// 内容（`TextFieldState.text`）とカーソル位置（`TextFieldState.cursor`）を扱う。内容は自分で持つか、
/// `TextField(text:state:placeholder:style:placeholderStyle:showsCursor:)` に `Binding` で渡すプロパティを
/// 読み書きする。カーソル位置はどちらの場合もここに置く。
///
/// - Invariant: 内容もカーソル位置も書記素クラスタ（`Character`）単位で、
///   国旗や ZWJ で結合した絵文字も 1 文字として数える。
@MainActor
public final class TextFieldState {
    private var ownedCharacters: [Character]
    private var textBinding: Binding<String>?
    private var storedCursor: Int

    /// 編集の対象になる文字の並び。
    private var characters: [Character] {
        get {
            guard let textBinding else { return ownedCharacters }
            return TextFieldState.sanitizedCharacters(of: textBinding.wrappedValue)
        }
        set {
            guard let textBinding else {
                ownedCharacters = newValue
                return
            }
            let text = String(newValue)
            // 比べずに書き戻したくなるが、先頭での Ctrl+U のように何も変えない編集でも
            // `Binding` で渡すプロパティへ代入される。TUIKit を使う開発者が、`Binding(_:_:)` にキーパスで
            // 渡したプロパティや、`Binding(get:set:)` の `set` で代入するプロパティに `didSet` を書いていれば、
            // 値が変わらないのに `didSet` が呼び出される。
            guard text != textBinding.wrappedValue else { return }
            textBinding.wrappedValue = text
        }
    }

    /// カーソルの文字インデックス（0 〜 文字数）。
    ///
    /// - Note: `Binding` で渡すプロパティが `TextFieldState` の外で書き換えられ、カーソル位置より
    ///   短くなると、カーソルは末尾に来る。
    public var cursor: Int {
        min(storedCursor, characters.count)
    }

    /// 直前の描画でカーソルを置いた画面上の位置。まだ描画していなければ `nil`。
    ///
    /// - Note: IME の変換中の文字と変換候補の一覧は、端末エミュレータが本物のカーソル位置に表示する。
    ///   入力欄にフォーカスがある間、`Component.cursorPosition` でこの値を返すと、
    ///   変換中の文字が入力欄の上に出る。返さなければ `Renderer` が最後に書き込んだ位置に出る。
    public internal(set) var renderedCursorPoint: Point?

    /// 初期の文字列を指定して `TextFieldState` を作る。
    ///
    /// - Parameters:
    ///   - text: 初期の文字列。1 行に置けない文字は取り除かれる。
    /// - Postcondition: カーソルは末尾に来る。
    public init(text: String = "") {
        self.ownedCharacters = TextFieldState.sanitizedCharacters(of: text)
        self.storedCursor = ownedCharacters.count
    }

    /// 内容の読み書きを `text` へ向ける。
    ///
    /// - Parameters:
    ///   - text: 内容を持つプロパティを読み書きする `Binding`。
    func bind(_ text: Binding<String>) {
        textBinding = text
    }

    /// 現在の文字列。
    public var text: String {
        String(characters)
    }

    /// 文字列が空か。
    public var isEmpty: Bool { characters.isEmpty }

    /// カーソル位置までの表示幅を返す。
    ///
    /// - Parameters:
    ///   - ambiguous: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。省略すると `DisplayWidth.defaultAmbiguousWidth` に従う。
    /// - Returns: 先頭からカーソルの直前の文字までの `Cell` の数。
    public func cursorColumn(
        ambiguous: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) -> Int {
        DisplayWidth.width(of: String(characters.prefix(cursor)), ambiguous: ambiguous)
    }

    /// 文字列を置き換える。
    ///
    /// - Parameters:
    ///   - text: 新しい文字列。1 行に置けない文字は取り除かれる。
    /// - Postcondition: カーソルは末尾に来る。
    public func setText(_ text: String) {
        characters = TextFieldState.sanitizedCharacters(of: text)
        storedCursor = characters.count
    }

    /// カーソル位置へ 1 文字を挿入する。
    ///
    /// - Parameters:
    ///   - character: 挿入する文字。改行とタブは空白 1 個に置き換え、
    ///     ほかの制御文字は挿入しない。
    public func insert(_ character: Character) {
        guard let allowed = TextFieldState.sanitized(character) else { return }
        replace(cursor..<cursor, with: String(allowed))
    }

    /// カーソル位置へ文字列を挿入する。貼り付けもここを通る。
    ///
    /// - Parameters:
    ///   - text: 挿入する文字列。1 行に置けない文字は取り除かれる。
    public func insert(contentsOf text: String) {
        let inserted = TextFieldState.sanitizedText(text)
        guard !inserted.isEmpty else { return }
        replace(cursor..<cursor, with: inserted)
    }

    // 幅 0 の制御文字が残るとカーソル移動が止まったように見える。
    // `TextFieldState` へ文字が入るところのすべてで、この判定を通すこと。

    /// 1 行の入力欄に置ける文字へ整える。
    ///
    /// - Parameters:
    ///   - character: 整える文字。
    /// - Returns: 改行（`\r\n` は 1 つの `Character` なのでまとめて 1 つ）とタブは空白 1 個、
    ///   ほかの制御文字は `nil`。それ以外はそのまま。
    private static func sanitized(_ character: Character) -> Character? {
        if character.isNewline || character == "\t" { return " " }
        guard let first = character.unicodeScalars.first else { return nil }
        if first.value < 0x20 || (first.value >= 0x7F && first.value < 0xA0) {
            return nil
        }
        return character
    }

    /// 1 行の入力欄に置ける文字だけを取り出す。
    ///
    /// - Parameters:
    ///   - text: 整える文字列。
    /// - Returns: 書記素クラスタで区切り直した文字の並び。
    private static func sanitizedCharacters(of text: String) -> [Character] {
        // 制御文字を取り除くと前後が 1 つの書記素クラスタになることがある。
        // `compactMap` の結果をそのまま返してはいけない。
        Array(String(text.compactMap { sanitized($0) }))
    }

    /// 1 行の入力欄に置ける文字だけにした文字列。プレースホルダにも同じ規則を使う。
    ///
    /// - Parameters:
    ///   - text: 整える文字列。
    /// - Returns: 1 行に置けない文字を取り除いた文字列。
    static func sanitizedText(_ text: String) -> String {
        String(sanitizedCharacters(of: text))
    }

    /// カーソルの直前の 1 文字を削除する。
    ///
    /// - Returns: 削除したら `true`。カーソルが先頭にあれば `false`。
    @discardableResult
    public func deleteBackward() -> Bool {
        guard cursor > 0 else { return false }
        replace((cursor - 1)..<cursor, with: "")
        return true
    }

    /// カーソル位置の 1 文字を削除する。
    ///
    /// - Returns: 削除したら `true`。カーソルが末尾にあれば `false`。
    @discardableResult
    public func deleteForward() -> Bool {
        guard cursor < characters.count else { return false }
        replace(cursor..<(cursor + 1), with: "")
        return true
    }

    /// 先頭からカーソルまでを削除する。
    public func deleteToStart() {
        replace(0..<cursor, with: "")
    }

    /// カーソルから末尾までを削除する。
    public func deleteToEnd() {
        replace(cursor..<characters.count, with: "")
    }

    /// `range` の文字を `text` に置き換える。
    ///
    /// - Parameters:
    ///   - range: 置き換える範囲の文字インデックス。
    ///   - text: 置き換えたあとに入る文字列。
    /// - Postcondition: 内容は書記素クラスタで区切り直され、カーソルは `text` の末尾に来る。
    ///   `text` が前後と 1 つのクラスタに結合した場合は、そのクラスタの後ろに来る。
    private func replace(_ range: Range<Int>, with text: String) {
        let current = characters
        let head = String(current[..<range.lowerBound]) + text
        let tail = String(current[range.upperBound...])
        let replaced = Array(head + tail)
        characters = replaced
        storedCursor = TextFieldState.characterIndex(in: replaced, afterUTF8Length: head.utf8.count)
    }

    /// 先頭から UTF-8 で `length` バイトの位置にあたる文字インデックス。
    ///
    /// - Parameters:
    ///   - characters: 位置を探す文字の並び。
    ///   - length: 先頭から数えた UTF-8 のバイト数。
    /// - Returns: その位置の文字インデックス。位置が書記素クラスタの内部に来る場合は、
    ///   そのクラスタの後ろ。
    private static func characterIndex(in characters: [Character], afterUTF8Length length: Int) -> Int {
        var consumed = 0
        var index = 0
        while index < characters.count && consumed < length {
            consumed += String(characters[index]).utf8.count
            index += 1
        }
        return index
    }

    /// カーソルを 1 文字左へ動かす。
    public func moveLeft() {
        storedCursor = max(0, cursor - 1)
    }

    /// カーソルを 1 文字右へ動かす。
    public func moveRight() {
        storedCursor = min(characters.count, cursor + 1)
    }

    /// カーソルを先頭へ動かす。
    public func moveToStart() {
        storedCursor = 0
    }

    /// カーソルを末尾へ動かす。
    public func moveToEnd() {
        storedCursor = characters.count
    }

    /// 文字入力・カーソル移動・削除・貼り付けを処理する。
    ///
    /// - Parameters:
    ///   - event: 処理する `InputEvent`。
    /// - Returns: 内容やカーソルを動かしたら `true`。
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

    /// キー入力を処理する。
    ///
    /// - Parameters:
    ///   - event: 押されたキー。
    /// - Returns: 内容やカーソルを動かしたら `true`。
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
public struct TextField: PrimitiveView {
    /// カーソル位置を持つ `TextFieldState`。`Binding` を渡さずに作った場合は内容も持つ。
    public var state: TextFieldState
    /// 空のときに表示する文字列。
    public var placeholder: String
    /// 文字のスタイル。
    public var style: Style
    /// プレースホルダのスタイル。
    public var placeholderStyle: Style
    /// カーソル位置を反転表示する（`TerminalApp` に準拠する型が `Component.cursorPosition` で
    /// 端末エミュレータのカーソルを出す場合は `false`）。
    public var showsCursor: Bool

    /// `Binding` で渡すプロパティの文字列を編集する `TextField` を作る。
    ///
    /// - Parameters:
    ///   - text: 編集する文字列を持つプロパティを読み書きする `Binding`。
    ///   - state: カーソル位置を持つ `TextFieldState`。内容は持たず、`text` を読み書きする。
    ///   - placeholder: 空のときに表示する文字列。
    ///   - style: 文字のスタイル。
    ///   - placeholderStyle: プレースホルダのスタイル。
    ///   - showsCursor: カーソル位置を反転表示するか。
    /// - Postcondition: `state` は以後、内容を `text` から読み、編集の結果を `text` へ書き戻す。
    ///   書き戻すのは `state.handle(_:)` などの編集の中だけで、描画では書き戻さない。
    public init(
        text: Binding<String>,
        state: TextFieldState,
        placeholder: String = "",
        style: Style = .plain,
        placeholderStyle: Style = Style(foreground: .brightBlack),
        showsCursor: Bool = true
    ) {
        state.bind(text)
        self.init(
            state: state,
            placeholder: placeholder,
            style: style,
            placeholderStyle: placeholderStyle,
            showsCursor: showsCursor
        )
    }

    /// 内容も持つ `TextFieldState` と見た目を指定して `TextField` を作る。
    ///
    /// - Parameters:
    ///   - state: 内容とカーソル位置を持つ `TextFieldState`。
    ///   - placeholder: 空のときに表示する文字列。
    ///   - style: 文字のスタイル。
    ///   - placeholderStyle: プレースホルダのスタイル。
    ///   - showsCursor: カーソル位置を反転表示するか。
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

    /// `LayoutTraits.horizontalFlex` だけを 1 にした `LayoutTraits` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `LayoutTraits.horizontalFlex` が 1、`LayoutTraits.verticalFlex` が 0 の `LayoutTraits`。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        LayoutTraits(horizontalFlex: 1, verticalFlex: 0)
    }

    /// `proposal` の幅いっぱいで、高さが 1 を超えない `Size` を返す。
    ///
    /// - Parameters:
    ///   - proposal: `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡された `Size`。
    ///   - context: 別の `View` のメソッドを呼び出すための `RenderContext`。
    /// - Returns: `proposal` の幅と、1 と `proposal.height` の小さい方を高さにした `Size`。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        Size(width: proposal.width, height: min(1, proposal.height))
    }

    /// 入力欄の幅が `width` のときに、スクロールして隠す先頭の `Cell` の数を返す。
    ///
    /// - Parameters:
    ///   - width: 入力欄に使える幅。
    ///   - ambiguous: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。省略すると `DisplayWidth.defaultAmbiguousWidth` に従う。
    /// - Returns: 隠す `Cell` の数。カーソルが幅の中に収まっていれば 0。
    /// - Postcondition: 全角文字を途中で割らない。
    public func scrollOffset(
        forWidth width: Int,
        ambiguous: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) -> Int {
        guard width > 0 else { return 0 }
        let column = state.cursorColumn(ambiguous: ambiguous)
        guard column >= width else { return 0 }

        // 必要な `Cell` の数で切ってはいけない。全角文字の途中で切れると左端が空白になる。
        // 文字の区切りまで切り上げる。
        let required = column - width + 1
        var offset = 0
        for character in state.text {
            if offset >= required { break }
            offset += DisplayWidth.width(of: character, ambiguous: ambiguous)
        }
        return offset
    }

    /// 内容、またはプレースホルダとカーソルを描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - rect: 描画する矩形。使うのは最初の 1 行だけ。
    ///   - context: 文字列の幅を測るときに `RenderContext.ambiguousWidth` を読む `RenderContext`。
    /// - Postcondition: `state.renderedCursorPoint` がカーソルの画面上の位置に更新される。
    ///   描く領域がなければ `nil` になる。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        guard rect.width > 0, rect.height > 0 else {
            state.renderedCursorPoint = nil
            return
        }
        let row = Rect(x: rect.minX, y: rect.minY, width: rect.width, height: 1)
        buffer.fill(row, with: Cell(character: " ", style: style))

        if state.isEmpty && !placeholder.isEmpty {
            buffer.write(
                DisplayWidth.truncate(
                    TextFieldState.sanitizedText(placeholder),
                    to: rect.width,
                    ambiguous: context.ambiguousWidth
                ),
                at: Point(x: rect.minX, y: rect.minY),
                style: placeholderStyle,
                clippedTo: row
            )
            // プレースホルダを表示している間はカーソルを置かずに済ませたくなるが、置かないと
            // 空の入力欄のどこに入力されるかが見えない。
            placeCursor(into: &buffer, at: Point(x: rect.minX, y: rect.minY), in: rect)
            return
        }

        let offset = scrollOffset(forWidth: rect.width, ambiguous: context.ambiguousWidth)
        buffer.write(
            state.text,
            at: Point(x: rect.minX - offset, y: rect.minY),
            style: style,
            clippedTo: row
        )

        placeCursor(
            into: &buffer,
            at: Point(
                x: rect.minX + state.cursorColumn(ambiguous: context.ambiguousWidth) - offset,
                y: rect.minY
            ),
            in: rect
        )
    }

    /// カーソルの位置を `TextFieldState.renderedCursorPoint` へ記録し、その `Cell` を反転させる。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。
    ///   - point: カーソルを置く `Cell` の位置。
    ///   - rect: 入力欄の矩形。この外へは描かない。
    /// - Postcondition: `state.renderedCursorPoint` が `point`（矩形の外なら `nil`）になる。
    private func placeCursor(into buffer: inout Buffer, at point: Point, in rect: Rect) {
        guard point.x >= rect.minX, point.x < rect.maxX else {
            state.renderedCursorPoint = nil
            return
        }
        // 反転表示をやめても IME に渡す位置は要る。記録を `showsCursor` で止めてはいけない。
        state.renderedCursorPoint = point

        guard showsCursor else { return }
        var cell = buffer[point.x, point.y]
        cell.style = cell.style.adding(.reverse)
        cell.isContinuation = false
        buffer[point.x, point.y] = cell
    }
}
