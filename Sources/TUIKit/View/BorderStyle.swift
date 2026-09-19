/// 枠線に使う文字の組み合わせ。
///
/// 枠線は 1 セルずつ書き込まれるので、どの文字も表示幅が 1 桁でなければならない。
public struct BorderStyle: Hashable, Sendable {
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

    /// 表示幅が 1 桁の文字だけを通し、そうでなければ `fallback` を返す。
    private static func singleWidth(_ character: Character, fallback: Character) -> Character {
        DisplayWidth.width(of: character) == 1 ? character : fallback
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
