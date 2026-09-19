/// 太字や下線などの文字装飾。
public struct TextAttributes: OptionSet, Hashable, Sendable {
    /// 各装飾をビットで表した値。
    public let rawValue: UInt16

    /// ビットの並びから装飾の組を作る。
    ///
    /// - Parameters:
    ///   - rawValue: 各装飾をビットで表した値。
    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    /// 太字。
    public static let bold = TextAttributes(rawValue: 1 << 0)
    /// 減光。
    public static let dim = TextAttributes(rawValue: 1 << 1)
    /// 斜体。
    public static let italic = TextAttributes(rawValue: 1 << 2)
    /// 下線。
    public static let underline = TextAttributes(rawValue: 1 << 3)
    /// 点滅。
    public static let blink = TextAttributes(rawValue: 1 << 4)
    /// 文字色と背景色の反転。
    public static let reverse = TextAttributes(rawValue: 1 << 5)
    /// 非表示。
    public static let hidden = TextAttributes(rawValue: 1 << 6)
    /// 打ち消し線。
    public static let strikethrough = TextAttributes(rawValue: 1 << 7)

    /// 装飾と、それを有効にする SGR コードの対応表。
    private static let codeTable: [(attribute: TextAttributes, code: Int)] = [
        (.bold, 1),
        (.dim, 2),
        (.italic, 3),
        (.underline, 4),
        (.blink, 5),
        (.reverse, 7),
        (.hidden, 8),
        (.strikethrough, 9),
    ]

    /// 有効化に必要な SGR パラメータ列。
    public var enableParameters: [String] {
        TextAttributes.codeTable
            .filter { contains($0.attribute) }
            .map { String($0.code) }
    }
}
