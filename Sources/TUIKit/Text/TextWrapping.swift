/// 文字列の折り返し方法。
public enum WrapMode: Hashable, Sendable {
    /// 折り返さず、はみ出した部分は切り捨てる。
    case none
    /// 折り返さず、末尾を省略記号に置き換える。
    case truncate
    /// 単語境界（空白）で折り返す。単語が 1 行に収まらない場合は文字単位で分割する。
    case word
    /// 文字単位で折り返す。
    case character
}

/// 表示幅を考慮した行分割。
public enum TextWrapping {

    /// `text` を幅 `width` に収まる行の配列へ分割する。
    ///
    /// 改行文字は常に行の区切りとして扱う。LF（`\n`）だけでなく、
    /// CRLF（`\r\n`）・単独の CR（`\r`）も 1 つの改行として扱う。
    /// タブは `tabSize` 桁ごとのタブストップまでの空白へ展開する。
    ///
    /// - Parameters:
    ///   - text: 分割する文字列。
    ///   - width: 1 行に許す表示幅。0 以下なら、各段落を空行として返す。
    ///   - mode: 折り返しの方法。
    ///   - tabSize: タブストップの間隔。
    /// - Returns: 各行の文字列。タブは展開済み。
    public static func wrap(
        _ text: String,
        width: Int,
        mode: WrapMode,
        tabSize: Int = TabExpansion.defaultSize
    ) -> [String] {
        // 幅を計算する前に展開する。あとで展開すると、`DisplayWidth` が計算した幅と
        // 実際に描画される幅が食い違う。
        let paragraphs = TabExpansion.expand(text, tabSize: tabSize)
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .map(String.init)
        if width <= 0 { return paragraphs.map { _ in "" } }

        var lines: [String] = []
        for paragraph in paragraphs {
            switch mode {
            case .none:
                lines.append(String(DisplayWidth.prefix(of: paragraph, width: width)))
            case .truncate:
                lines.append(DisplayWidth.truncate(paragraph, to: width))
            case .character:
                lines.append(contentsOf: splitByCharacter(paragraph, width: width))
            case .word:
                lines.append(contentsOf: splitByWord(paragraph, width: width))
            }
        }
        return lines
    }

    private static func splitByCharacter(_ text: String, width: Int) -> [String] {
        if text.isEmpty { return [""] }

        var lines: [String] = []
        var current = ""
        var used = 0
        for character in text {
            let characterWidth = DisplayWidth.width(of: character)
            if used + characterWidth > width && !current.isEmpty {
                lines.append(current)
                current = ""
                used = 0
            }
            current.append(character)
            used += characterWidth
        }
        lines.append(current)
        return lines
    }

    private static func splitByWord(_ text: String, width: Int) -> [String] {
        if text.isEmpty { return [""] }

        var lines: [String] = []
        var current = ""
        var used = 0

        func flush() {
            lines.append(trimmingTrailingSpaces(current))
            current = ""
            used = 0
        }

        for word in tokenize(text) {
            let wordWidth = DisplayWidth.width(of: word)

            if word.allSatisfy({ $0 == " " }) {
                if current.isEmpty { continue }
                if used + wordWidth > width {
                    flush()
                    continue
                }
                current += word
                used += wordWidth
                continue
            }

            if used + wordWidth <= width {
                current += word
                used += wordWidth
                continue
            }

            if !current.isEmpty {
                flush()
            }

            if wordWidth <= width {
                current = word
                used = wordWidth
            } else {
                let pieces = splitByCharacter(word, width: width)
                lines.append(contentsOf: pieces.dropLast())
                current = pieces.last ?? ""
                used = DisplayWidth.width(of: current)
            }
        }

        lines.append(trimmingTrailingSpaces(current))
        return lines
    }

    private static func trimmingTrailingSpaces(_ text: String) -> String {
        var result = text
        while let last = result.last, last == " " || last == "\t" {
            result.removeLast()
        }
        return result
    }

    /// 空白の並びと非空白の並びを交互に取り出す。
    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace: Bool? = nil

        for character in text {
            let isSpace = (character == " " || character == "\t")
            if currentIsSpace == nil || currentIsSpace == isSpace {
                current.append(character)
            } else {
                tokens.append(current)
                current = String(character)
            }
            currentIsSpace = isSpace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
