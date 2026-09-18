/// 枠線に使う文字の組み合わせ。
public struct BorderStyle: Hashable, Sendable {
    public var topLeft: Character
    public var top: Character
    public var topRight: Character
    public var left: Character
    public var right: Character
    public var bottomLeft: Character
    public var bottom: Character
    public var bottomRight: Character

    public init(
        topLeft: Character,
        top: Character,
        topRight: Character,
        left: Character,
        right: Character,
        bottomLeft: Character,
        bottom: Character,
        bottomRight: Character
    ) {
        self.topLeft = topLeft
        self.top = top
        self.topRight = topRight
        self.left = left
        self.right = right
        self.bottomLeft = bottomLeft
        self.bottom = bottom
        self.bottomRight = bottomRight
    }

    /// 枠線に使う 8 文字。
    public var characters: [Character] {
        [topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight]
    }

    /// すべての文字が 1 桁に収まるか。
    ///
    /// 罫線素片は East Asian Width が Ambiguous なので、`DisplayWidth.ambiguousWidth`
    /// が `.wide` のときは 2 桁になり、1 セル 1 文字で描く枠線が崩れる。
    public var fitsInSingleColumn: Bool {
        characters.allSatisfy { DisplayWidth.width(of: $0) == 1 }
    }

    /// 細い実線。
    public static let single = BorderStyle(
        topLeft: "┌", top: "─", topRight: "┐",
        left: "│", right: "│",
        bottomLeft: "└", bottom: "─", bottomRight: "┘"
    )

    /// 角の丸い実線。
    public static let rounded = BorderStyle(
        topLeft: "╭", top: "─", topRight: "╮",
        left: "│", right: "│",
        bottomLeft: "╰", bottom: "─", bottomRight: "╯"
    )

    /// 二重線。
    public static let double = BorderStyle(
        topLeft: "╔", top: "═", topRight: "╗",
        left: "║", right: "║",
        bottomLeft: "╚", bottom: "═", bottomRight: "╝"
    )

    /// 太線。
    public static let thick = BorderStyle(
        topLeft: "┏", top: "━", topRight: "┓",
        left: "┃", right: "┃",
        bottomLeft: "┗", bottom: "━", bottomRight: "┛"
    )

    /// 罫線素片を使わない ASCII 版。
    public static let ascii = BorderStyle(
        topLeft: "+", top: "-", topRight: "+",
        left: "|", right: "|",
        bottomLeft: "+", bottom: "-", bottomRight: "+"
    )
}
