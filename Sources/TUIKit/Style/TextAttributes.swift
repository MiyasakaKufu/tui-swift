/// 太字や下線などの文字装飾。
public struct TextAttributes: OptionSet, Hashable, Sendable {
    public let rawValue: UInt16

    public init(rawValue: UInt16) {
        self.rawValue = rawValue
    }

    public static let bold = TextAttributes(rawValue: 1 << 0)
    public static let dim = TextAttributes(rawValue: 1 << 1)
    public static let italic = TextAttributes(rawValue: 1 << 2)
    public static let underline = TextAttributes(rawValue: 1 << 3)
    public static let blink = TextAttributes(rawValue: 1 << 4)
    public static let reverse = TextAttributes(rawValue: 1 << 5)
    public static let hidden = TextAttributes(rawValue: 1 << 6)
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
