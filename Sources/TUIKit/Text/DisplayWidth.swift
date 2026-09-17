/// 文字が端末上で占める桁数の計算。
///
/// 東アジアの全角文字と絵文字は 2 桁、結合文字や制御文字は 0 桁として扱う。
public enum DisplayWidth {

    /// East Asian Width が Wide / Fullwidth のコードポイント範囲（昇順）。
    private static let wideRanges: [ClosedRange<UInt32>] = [
        0x1100...0x115F,    // ハングル字母
        0x2E80...0x303E,    // CJK 部首補助〜CJK 記号
        0x3041...0x33FF,    // かな〜CJK 互換
        0x3400...0x4DBF,    // CJK 統合漢字拡張 A
        0x4E00...0x9FFF,    // CJK 統合漢字
        0xA000...0xA4CF,    // イ文字
        0xA960...0xA97F,    // ハングル字母拡張 A
        0xAC00...0xD7A3,    // ハングル音節
        0xF900...0xFAFF,    // CJK 互換漢字
        0xFE10...0xFE19,    // 縦書き用記号
        0xFE30...0xFE6F,    // CJK 互換形〜小字形
        0xFF00...0xFF60,    // 全角 ASCII
        0xFFE0...0xFFE6,    // 全角記号
        0x16FE0...0x16FE4,
        0x17000...0x18AFF,  // 西夏文字
        0x1B000...0x1B2FF,  // 仮名補助
        0x1F300...0x1F64F,  // 記号・絵文字
        0x1F900...0x1F9FF,  // 補助記号・絵文字
        0x1FA70...0x1FAFF,
        0x20000...0x2FFFD,  // CJK 統合漢字拡張 B 以降
        0x30000...0x3FFFD,
    ]

    /// 1 文字（書記素クラスタ）の表示幅。
    public static func width(of character: Character) -> Int {
        guard let first = character.unicodeScalars.first else { return 0 }

        // 制御文字は幅を持たない。
        if first.value < 0x20 || (first.value >= 0x7F && first.value < 0xA0) {
            return 0
        }

        // 異体字セレクタ 16 が付いていれば絵文字表示（全角）。
        if character.unicodeScalars.contains(where: { $0.value == 0xFE0F }) {
            return 2
        }

        if first.properties.isEmojiPresentation { return 2 }
        if isWide(first) { return 2 }
        if isZeroWidth(first) { return 0 }
        return 1
    }

    /// 文字列全体の表示幅。
    public static func width(of string: String) -> Int {
        var total = 0
        for character in string {
            total += width(of: character)
        }
        return total
    }

    /// 表示幅が `limit` を超えないように末尾を切り詰める。
    ///
    /// 切り詰めが発生した場合は `ellipsis` を付加する（`ellipsis` 自体の幅も `limit` に含む）。
    public static func truncate(_ string: String, to limit: Int, ellipsis: String = "…") -> String {
        if limit <= 0 { return "" }
        if width(of: string) <= limit { return string }

        let ellipsisWidth = width(of: ellipsis)
        if ellipsisWidth >= limit {
            return String(prefix(of: string, width: limit))
        }

        let head = prefix(of: string, width: limit - ellipsisWidth)
        return String(head) + ellipsis
    }

    /// 表示幅が `limit` を超えない範囲の接頭辞。
    public static func prefix(of string: String, width limit: Int) -> Substring {
        if limit <= 0 { return string.prefix(0) }
        var used = 0
        var index = string.startIndex
        while index < string.endIndex {
            let characterWidth = width(of: string[index])
            if used + characterWidth > limit { break }
            used += characterWidth
            index = string.index(after: index)
        }
        return string[string.startIndex..<index]
    }

    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200B { return true }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return true
        default:
            return false
        }
    }

    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        if value < 0x1100 { return false }

        var low = 0
        var high = wideRanges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = wideRanges[middle]
            if value < range.lowerBound {
                high = middle - 1
            } else if value > range.upperBound {
                low = middle + 1
            } else {
                return true
            }
        }
        return false
    }
}
