/// タブ文字を、次のタブストップまでの空白へ展開する。
///
/// 端末はタブの幅を持たない制御文字として扱うため、描画する前に空白へ置き換える。
public enum TabExpansion {

    /// タブ幅の既定値。
    public static let defaultSize = 4

    /// `text` のタブを、次のタブストップまでの空白に置き換える。
    ///
    /// - Parameters:
    ///   - text: 展開する文字列。改行を含む場合、桁の積算は行ごとに 0 へ戻る。
    ///   - tabSize: タブストップの間隔。0 以下ならタブを取り除く。
    ///   - startColumn: 1 行目の開始桁。行の途中から展開する場合に指定する。
    ///   - ambiguous: 桁を数えるときの曖昧幅の文字の扱い。省略すると
    ///     `DisplayWidth.defaultAmbiguousWidth` に従う。
    /// - Returns: タブを含まない文字列。
    public static func expand(
        _ text: String,
        tabSize: Int = TabExpansion.defaultSize,
        startColumn: Int = 0,
        ambiguous: DisplayWidth.AmbiguousWidth = DisplayWidth.defaultAmbiguousWidth
    ) -> String {
        guard text.contains("\t") else { return text }

        var result = ""
        result.reserveCapacity(text.count)
        var column = max(0, startColumn)

        for character in text {
            if character == "\t" {
                guard tabSize > 0 else { continue }
                let spaces = tabSize - (column % tabSize)
                result.append(String(repeating: " ", count: spaces))
                column += spaces
            } else if character.isNewline {
                result.append(character)
                column = 0
            } else {
                result.append(character)
                column += DisplayWidth.width(of: character, ambiguous: ambiguous)
            }
        }
        return result
    }
}
