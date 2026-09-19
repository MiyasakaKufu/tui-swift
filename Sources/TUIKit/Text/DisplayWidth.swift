#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// 文字が端末上で占める桁数の計算。
///
/// 東アジアの全角文字と絵文字は 2 桁、結合文字や制御文字は 0 桁として扱う。
/// East Asian Width が Ambiguous の文字（罫線素片、`…`、`█`、矢印など）は
/// 端末の設定によって 1 桁にも 2 桁にも表示されるため、`ambiguousWidth` で切り替える。
public enum DisplayWidth {

    /// East Asian Width が Ambiguous の文字を何桁として扱うか。
    public enum AmbiguousWidth: Int, Sendable {
        /// 1 桁として扱う。
        case narrow = 1
        /// 2 桁として扱う。
        case wide = 2
    }

    /// 曖昧幅の扱いを上書きする環境変数の名前。
    ///
    /// go-runewidth や tcell が見るものと同じ `RUNEWIDTH_EASTASIAN`。
    public static let ambiguousWidthEnvironmentVariable = "RUNEWIDTH_EASTASIAN"

    /// 曖昧幅の文字を何桁として扱うか。
    ///
    /// - Note: 初期値は最初に参照した時点で `resolveAmbiguousWidth()` から一度だけ決まる。
    ///   あとから環境変数を変えても反映されないため、切り替えるにはこのプロパティへ代入する。
    public static var ambiguousWidth: AmbiguousWidth = resolveAmbiguousWidth()

    // MARK: - 設定の解決

    /// 環境変数とロケールから、曖昧幅の扱いを決める。
    ///
    /// - Parameters:
    ///   - usingLocale: 環境変数が未設定のときに、ロケールからも推測するか。
    /// - Returns: 決まった扱い。どちらからも決まらなければ `.narrow`。
    public static func resolveAmbiguousWidth(usingLocale: Bool = false) -> AmbiguousWidth {
        if let fromEnvironment = ambiguousWidthFromEnvironment() { return fromEnvironment }
        if usingLocale, let fromLocale = ambiguousWidthFromLocale() { return fromLocale }
        return .narrow
    }

    /// 環境変数 `RUNEWIDTH_EASTASIAN` から曖昧幅の扱いを読む。
    ///
    /// - Returns: 値が `1` なら `.wide`、ほかの値なら `.narrow`。
    ///   環境変数が未設定か空文字列なら `nil`。
    public static func ambiguousWidthFromEnvironment() -> AmbiguousWidth? {
        parseAmbiguousWidth(environmentValue: environmentString(ambiguousWidthEnvironmentVariable))
    }

    /// ロケールから曖昧幅の扱いを推測する。
    ///
    /// `LC_ALL` `LC_CTYPE` `LANG` の順に探し、最初に見つかった値だけを見る。
    ///
    /// - Returns: 文字集合が UTF-8 で、言語が ja / ko / zh なら `.wide`、
    ///   それ以外なら `.narrow`。3 つとも未設定なら `nil`。
    public static func ambiguousWidthFromLocale() -> AmbiguousWidth? {
        for name in ["LC_ALL", "LC_CTYPE", "LANG"] {
            guard let value = environmentString(name), !value.isEmpty else { continue }
            return parseAmbiguousWidth(localeValue: value)
        }
        return nil
    }

    /// 曖昧幅を 2 桁として扱う言語。
    private static let eastAsianLanguages: Set<String> = ["ja", "ko", "zh"]

    /// 環境変数 `RUNEWIDTH_EASTASIAN` の値を解釈する。
    ///
    /// - Parameters:
    ///   - value: 環境変数の値。未設定なら `nil`。
    /// - Returns: `1` なら `.wide`、ほかの値なら `.narrow`。`nil` か空文字列なら `nil`。
    static func parseAmbiguousWidth(environmentValue value: String?) -> AmbiguousWidth? {
        guard let value, !value.isEmpty else { return nil }
        return value == "1" ? .wide : .narrow
    }

    /// `LC_ALL` などのロケール名を解釈する。
    ///
    /// - Parameters:
    ///   - value: ロケール名。未設定なら `nil`。
    /// - Returns: 文字集合が UTF-8 で、言語が ja / ko / zh なら `.wide`、
    ///   それ以外なら `.narrow`。`nil` か空文字列なら `nil`。
    static func parseAmbiguousWidth(localeValue value: String?) -> AmbiguousWidth? {
        guard let value, !value.isEmpty else { return nil }

        // POSIX のロケール名は "言語[_地域][.文字集合][@修飾子]" の形をとる。
        let body = value.split(separator: "@", maxSplits: 1).first ?? ""
        let parts = body.split(separator: ".", maxSplits: 1)
        let territory = parts.first ?? ""
        let language = (territory.split(separator: "_").first ?? "").lowercased()
        let codeset = parts.count > 1 ? normalizedCodeset(parts[1]) : ""

        // C や eucJP のロケールで端末がどちらの幅を選ぶかは決まっていない。推測で 2 桁にしない。
        guard codeset == "utf8" else { return .narrow }
        return eastAsianLanguages.contains(language) ? .wide : .narrow
    }

    /// 文字集合名を比較できる形に揃える。
    ///
    /// - Parameters:
    ///   - value: `UTF-8` `utf8` `eucJP` のような文字集合名。
    /// - Returns: 小文字にし、`-` と `_` を取り除いた文字列。
    private static func normalizedCodeset(_ value: Substring) -> String {
        value.lowercased().filter { $0 != "-" && $0 != "_" }
    }

    /// 環境変数の値を読む。
    ///
    /// - Parameters:
    ///   - name: 環境変数の名前。
    /// - Returns: 設定されていればその値、なければ `nil`。
    private static func environmentString(_ name: String) -> String? {
        guard let raw = getenv(name) else { return nil }
        return String(cString: raw)
    }

    // MARK: - 幅の計算

    /// 1 文字（書記素クラスタ）の表示幅を返す。
    ///
    /// - Parameters:
    ///   - character: 幅を求める文字。
    ///   - ambiguous: 曖昧幅の文字の扱い。省略すると `ambiguousWidth` に従う。
    /// - Returns: 桁数。全角文字と絵文字は 2、結合文字と制御文字は 0。
    public static func width(
        of character: Character,
        ambiguous: AmbiguousWidth = DisplayWidth.ambiguousWidth
    ) -> Int {
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
        if isAmbiguous(first) { return ambiguous.rawValue }
        return 1
    }

    /// 文字列全体の表示幅を返す。
    ///
    /// - Parameters:
    ///   - string: 幅を求める文字列。
    ///   - ambiguous: 曖昧幅の文字の扱い。省略すると `ambiguousWidth` に従う。
    /// - Returns: 各文字の桁数の合計。
    public static func width(
        of string: String,
        ambiguous: AmbiguousWidth = DisplayWidth.ambiguousWidth
    ) -> Int {
        var total = 0
        for character in string {
            total += width(of: character, ambiguous: ambiguous)
        }
        return total
    }

    /// 表示幅が `limit` を超えないように末尾を切り詰める。
    ///
    /// - Parameters:
    ///   - string: 切り詰める文字列。
    ///   - limit: 許容する表示幅。0 以下なら空文字列を返す。
    ///   - ellipsis: 切り詰めたときに末尾へ付ける文字列。
    ///   - ambiguous: 曖昧幅の文字の扱い。省略すると `ambiguousWidth` に従う。
    /// - Returns: 表示幅が `limit` 以下の文字列。切り詰めが起きなければ `string` そのまま。
    /// - Note: `ellipsis` 自身の幅も `limit` に含める。
    ///   `ellipsis` だけで `limit` に達する場合は付けずに切り詰める。
    public static func truncate(
        _ string: String,
        to limit: Int,
        ellipsis: String = "…",
        ambiguous: AmbiguousWidth = DisplayWidth.ambiguousWidth
    ) -> String {
        if limit <= 0 { return "" }
        if width(of: string, ambiguous: ambiguous) <= limit { return string }

        let ellipsisWidth = width(of: ellipsis, ambiguous: ambiguous)
        if ellipsisWidth >= limit {
            return String(prefix(of: string, width: limit, ambiguous: ambiguous))
        }

        let head = prefix(of: string, width: limit - ellipsisWidth, ambiguous: ambiguous)
        return String(head) + ellipsis
    }

    /// 表示幅が `limit` を超えない範囲の接頭辞を返す。
    ///
    /// - Parameters:
    ///   - string: 切り出す元の文字列。
    ///   - limit: 許容する表示幅。0 以下なら空の `Substring` を返す。
    ///   - ambiguous: 曖昧幅の文字の扱い。省略すると `ambiguousWidth` に従う。
    /// - Returns: 表示幅が `limit` 以下になる最長の接頭辞。
    /// - Postcondition: 全角文字を途中で割らない。
    public static func prefix(
        of string: String,
        width limit: Int,
        ambiguous: AmbiguousWidth = DisplayWidth.ambiguousWidth
    ) -> Substring {
        if limit <= 0 { return string.prefix(0) }
        var used = 0
        var index = string.startIndex
        while index < string.endIndex {
            let characterWidth = width(of: string[index], ambiguous: ambiguous)
            if used + characterWidth > limit { break }
            used += characterWidth
            index = string.index(after: index)
        }
        return string[string.startIndex..<index]
    }

    /// スカラーが幅を持たないかを調べる。
    ///
    /// - Parameters:
    ///   - scalar: 調べるスカラー。
    /// - Returns: 結合文字・囲み文字・書式文字・ゼロ幅スペースなら `true`。
    private static func isZeroWidth(_ scalar: Unicode.Scalar) -> Bool {
        if scalar.value == 0x200B { return true }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .enclosingMark, .format:
            return true
        default:
            return false
        }
    }

    /// スカラーが East Asian Width で Wide / Fullwidth かを調べる。
    ///
    /// - Parameters:
    ///   - scalar: 調べるスカラー。
    /// - Returns: `wideRanges` のいずれかに含まれれば `true`。
    private static func isWide(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x1100 && contains(wideRanges, scalar.value)
    }

    /// スカラーが East Asian Width で Ambiguous かを調べる。
    ///
    /// - Parameters:
    ///   - scalar: 調べるスカラー。
    /// - Returns: `ambiguousRanges` のいずれかに含まれれば `true`。
    private static func isAmbiguous(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value >= 0x00A1 && contains(ambiguousRanges, scalar.value)
    }

    /// 範囲表に値が含まれるかを調べる。
    ///
    /// - Parameters:
    ///   - ranges: 探索する範囲表。
    ///   - value: 探すコードポイント。
    /// - Returns: どれかの範囲に含まれれば `true`。
    /// - Precondition: `ranges` は昇順に並び、範囲どうしが重ならない。
    /// - Complexity: 範囲の個数を n として O(log n)。
    private static func contains(_ ranges: [ClosedRange<UInt32>], _ value: UInt32) -> Bool {
        var low = 0
        var high = ranges.count - 1
        while low <= high {
            let middle = (low + high) / 2
            let range = ranges[middle]
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

    // MARK: - 範囲表

    /// East Asian Width が Wide / Fullwidth のコードポイント範囲。
    ///
    /// - Invariant: 昇順に並び、範囲どうしが重ならない。
    static let wideRanges: [ClosedRange<UInt32>] = [
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

    /// East Asian Width が Ambiguous のコードポイント範囲。
    ///
    /// ラテン・ギリシャ・キリル文字の一部、記号、罫線素片、ブロック要素、私用領域が含まれる。
    ///
    /// - Invariant: 昇順に並び、範囲どうしが重ならない。
    static let ambiguousRanges: [ClosedRange<UInt32>] = [
        0x00A1...0x00A1, 0x00A4...0x00A4, 0x00A7...0x00A8,
        0x00AA...0x00AA, 0x00AD...0x00AE, 0x00B0...0x00B4,
        0x00B6...0x00BA, 0x00BC...0x00BF, 0x00C6...0x00C6,
        0x00D0...0x00D0, 0x00D7...0x00D8, 0x00DE...0x00E1,
        0x00E6...0x00E6, 0x00E8...0x00EA, 0x00EC...0x00ED,
        0x00F0...0x00F0, 0x00F2...0x00F3, 0x00F7...0x00FA,
        0x00FC...0x00FC, 0x00FE...0x00FE, 0x0101...0x0101,
        0x0111...0x0111, 0x0113...0x0113, 0x011B...0x011B,
        0x0126...0x0127, 0x012B...0x012B, 0x0131...0x0133,
        0x0138...0x0138, 0x013F...0x0142, 0x0144...0x0144,
        0x0148...0x014B, 0x014D...0x014D, 0x0152...0x0153,
        0x0166...0x0167, 0x016B...0x016B, 0x01CE...0x01CE,
        0x01D0...0x01D0, 0x01D2...0x01D2, 0x01D4...0x01D4,
        0x01D6...0x01D6, 0x01D8...0x01D8, 0x01DA...0x01DA,
        0x01DC...0x01DC, 0x0251...0x0251, 0x0261...0x0261,
        0x02C4...0x02C4, 0x02C7...0x02C7, 0x02C9...0x02CB,
        0x02CD...0x02CD, 0x02D0...0x02D0, 0x02D8...0x02DB,
        0x02DD...0x02DD, 0x02DF...0x02DF, 0x0300...0x036F,  // 結合文字（幅 0 が優先される）
        0x0391...0x03A1, 0x03A3...0x03A9, 0x03B1...0x03C1,
        0x03C3...0x03C9, 0x0401...0x0401, 0x0410...0x044F,
        0x0451...0x0451, 0x2010...0x2010, 0x2013...0x2016,
        0x2018...0x2019, 0x201C...0x201D, 0x2020...0x2022,
        0x2024...0x2027, 0x2030...0x2030, 0x2032...0x2033,
        0x2035...0x2035, 0x203B...0x203B, 0x203E...0x203E,
        0x2074...0x2074, 0x207F...0x207F, 0x2081...0x2084,
        0x20AC...0x20AC, 0x2103...0x2103, 0x2105...0x2105,
        0x2109...0x2109, 0x2113...0x2113, 0x2116...0x2116,
        0x2121...0x2122, 0x2126...0x2126, 0x212B...0x212B,
        0x2153...0x2154, 0x215B...0x215E, 0x2160...0x216B,
        0x2170...0x2179, 0x2189...0x2189, 0x2190...0x2199,  // 矢印
        0x21B8...0x21B9, 0x21D2...0x21D2, 0x21D4...0x21D4,
        0x21E7...0x21E7, 0x2200...0x2200, 0x2202...0x2203,
        0x2207...0x2208, 0x220B...0x220B, 0x220F...0x220F,
        0x2211...0x2211, 0x2215...0x2215, 0x221A...0x221A,
        0x221D...0x2220, 0x2223...0x2223, 0x2225...0x2225,
        0x2227...0x222C, 0x222E...0x222E, 0x2234...0x2237,
        0x223C...0x223D, 0x2248...0x2248, 0x224C...0x224C,
        0x2252...0x2252, 0x2260...0x2261, 0x2264...0x2267,
        0x226A...0x226B, 0x226E...0x226F, 0x2282...0x2283,
        0x2286...0x2287, 0x2295...0x2295, 0x2299...0x2299,
        0x22A5...0x22A5, 0x22BF...0x22BF, 0x2312...0x2312,
        0x2460...0x24E9, 0x24EB...0x254B,                   // 丸囲み数字〜罫線素片
        0x2550...0x2573,                                    // 罫線素片（二重線・斜線）
        0x2580...0x258F, 0x2592...0x2595,                   // ブロック要素
        0x25A0...0x25A1, 0x25A3...0x25A9, 0x25B2...0x25B3,
        0x25B6...0x25B7, 0x25BC...0x25BD, 0x25C0...0x25C1,
        0x25C6...0x25C8, 0x25CB...0x25CB, 0x25CE...0x25D1,
        0x25E2...0x25E5, 0x25EF...0x25EF, 0x2605...0x2606,
        0x2609...0x2609, 0x260E...0x260F, 0x261C...0x261C,
        0x261E...0x261E, 0x2640...0x2640, 0x2642...0x2642,
        0x2660...0x2661, 0x2663...0x2665, 0x2667...0x266A,
        0x266C...0x266D, 0x266F...0x266F, 0x269E...0x269F,
        0x26BF...0x26BF, 0x26C6...0x26CD, 0x26CF...0x26D3,
        0x26D5...0x26E1, 0x26E3...0x26E3, 0x26E8...0x26E9,
        0x26EB...0x26F1, 0x26F4...0x26F4, 0x26F6...0x26F9,
        0x26FB...0x26FC, 0x26FE...0x26FF, 0x273D...0x273D,
        0x2776...0x277F, 0x2B56...0x2B59, 0x3248...0x324F,
        0xE000...0xF8FF,                                    // 私用領域
        0xFFFD...0xFFFD,
        0x1F100...0x1F10A, 0x1F110...0x1F12D, 0x1F130...0x1F169,
        0x1F170...0x1F18D, 0x1F18F...0x1F190, 0x1F19B...0x1F1AC,
        0xE0100...0xE01EF,                                  // 異体字セレクタ（幅 0 が優先される）
        0xF0000...0xFFFFD, 0x100000...0x10FFFD,             // 私用領域（追加面）
    ]
}
