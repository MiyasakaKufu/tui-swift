/// 枠線に使う文字の組み合わせ。
public struct BorderStyle: Hashable, Sendable {
    // var に戻すと幅 1 桁という不変条件が壊れる。差し替えはイニシャライザ経由で。

    /// 左上の角の文字。
    public private(set) var topLeft: Character
    /// 上辺の文字。
    public private(set) var top: Character
    /// 右上の角の文字。
    public private(set) var topRight: Character
    /// 左辺の文字。
    public private(set) var left: Character
    /// 右辺の文字。
    public private(set) var right: Character
    /// 左下の角の文字。
    public private(set) var bottomLeft: Character
    /// 下辺の文字。
    public private(set) var bottom: Character
    /// 右下の角の文字。
    public private(set) var bottomRight: Character

    /// 8 方向の文字を指定して枠線の文字組みを作る。
    ///
    /// - Parameters:
    ///   - topLeft: 左上の角に置く文字。
    ///   - top: 上辺に並べる文字。
    ///   - topRight: 右上の角に置く文字。
    ///   - left: 左辺に並べる文字。
    ///   - right: 右辺に並べる文字。
    ///   - bottomLeft: 左下の角に置く文字。
    ///   - bottom: 下辺に並べる文字。
    ///   - bottomRight: 右下の角に置く文字。
    /// - Postcondition: 曖昧幅を 1 桁と数えても 1 桁にならない文字（全角文字や絵文字）は、
    ///   その位置の既定の文字（`single` と同じ細い実線）へ置き換わる。
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

    // `.narrow` を既定の曖昧幅に変えてはいけない。同じ引数から環境によって違う文字組みができる。
    // 曖昧幅が 2 桁のときの置き換え先（罫線素片）も 2 桁なので、置き換えても桁は揃わない。
    private static func singleWidth(_ character: Character, fallback: Character) -> Character {
        DisplayWidth.width(of: character, ambiguous: .narrow) == 1 ? character : fallback
    }

    /// 8 方向の文字がすべて 1 桁に収まるかを調べる。
    ///
    /// - Parameters:
    ///   - ambiguous: 曖昧幅の文字の扱い。省略すると `DisplayWidth.defaultAmbiguousWidth` に従う。
    /// - Returns: すべて 1 桁なら `true`。
    /// - Note: 罫線素片は East Asian Width が Ambiguous なので、`ambiguous` が `.wide` のときは
    ///   2 桁になる。`ascii` 以外の組み込みの文字組みは、どれも 1 桁に収まらない。
    public func fitsInSingleColumn(
        ambiguous: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) -> Bool {
        [topLeft, top, topRight, left, right, bottomLeft, bottom, bottomRight]
            .allSatisfy { DisplayWidth.width(of: $0, ambiguous: ambiguous) == 1 }
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
