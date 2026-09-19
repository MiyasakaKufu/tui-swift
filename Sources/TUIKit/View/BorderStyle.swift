/// 枠線に使う文字の組み合わせ。
public struct BorderStyle: Hashable, Sendable {
    // var に戻すと幅 1 桁という不変条件が壊れる。差し替えはイニシャライザ経由で。
    public private(set) var topLeft: Character
    public private(set) var top: Character
    public private(set) var topRight: Character
    public private(set) var left: Character
    public private(set) var right: Character
    public private(set) var bottomLeft: Character
    public private(set) var bottom: Character
    public private(set) var bottomRight: Character

    /// 8 方向の文字を指定して作る。
    ///
    /// 表示幅が 1 桁でない文字（全角文字や絵文字）を渡した場合は、その位置の既定の文字
    /// （`single` と同じ細い実線）へ置き換える。
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
        self.topLeft = Self.singleWidth(topLeft, fallback: "┌")
        self.top = Self.singleWidth(top, fallback: "─")
        self.topRight = Self.singleWidth(topRight, fallback: "┐")
        self.left = Self.singleWidth(left, fallback: "│")
        self.right = Self.singleWidth(right, fallback: "│")
        self.bottomLeft = Self.singleWidth(bottomLeft, fallback: "└")
        self.bottom = Self.singleWidth(bottom, fallback: "─")
        self.bottomRight = Self.singleWidth(bottomRight, fallback: "┘")
    }

    private static func singleWidth(_ character: Character, fallback: Character) -> Character {
        DisplayWidth.width(of: character) == 1 ? character : fallback
    }

    /// 8 方向の文字がすべて 1 桁に収まるか。
    ///
    /// - Note: 罫線素片は East Asian Width が Ambiguous なので、
    ///   `DisplayWidth.ambiguousWidth` が `.wide` のときは 2 桁になる。
    ///   このとき `init` の置き換え先（`single` と同じ罫線素片）も 2 桁なので、
    ///   置き換えても 1 桁には収まらない。
    public var fitsInSingleColumn: Bool {
        [topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight]
            .allSatisfy { DisplayWidth.width(of: $0) == 1 }
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
