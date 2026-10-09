/// タブ文字を、次のタブストップまでの空白へ展開する。
///
/// `DisplayWidth` はタブを `Cell` 0 個分の制御文字として数え、端末エミュレータはタブを受け取るとカーソルを
/// 自身のタブストップまで動かすため、`Cell` に書き込む前に空白へ置き換える。
public enum TabExpansion {

    /// `tabSize` 引数を省いたときのタブストップの間隔（`Cell` の数）。
    ///
    /// `TabExpansion.expand(_:tabSize:startColumn:ambiguous:)`・`TextWrapping.wrap(_:width:mode:tabSize:ambiguous:)`・
    /// `Text.init(_:style:wrap:alignment:tabSize:)` が使う。
    public static let defaultSize = 4

    /// `text` のタブを、次のタブストップまでの空白に置き換える。
    ///
    /// - Parameters:
    ///   - text: 展開する文字列。改行を含む場合、2 行目以降は前に並ぶ `Cell` の数を 0 としてタブストップを決める
    ///     （`startColumn` は 1 行目にだけ効く）。
    ///   - tabSize: タブストップの間隔。0 以下ならタブを取り除く。
    ///   - startColumn: `text` の前に、同じ行へすでに並んでいる `Cell` の数。行の途中から展開する場合に指定する。
    ///   - ambiguous: `Cell` の数を数えるときに使う `DisplayWidth.AmbiguousWidth`。
    ///     省略すると `DisplayWidth.defaultAmbiguousWidth` に従う。
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
