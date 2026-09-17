/// 画面 1 桁分の内容。
public struct Cell: Hashable, Sendable {
    /// 表示する書記素クラスタ。
    public var character: Character
    /// 見た目。
    public var style: Style
    /// 直前の全角文字が占める右半分の桁であることを示す。
    ///
    /// 継続セルは端末へ書き出さない（全角文字の描画によって既に埋まっているため）が、
    /// 差分計算では通常のセルと同じように比較される。
    public var isContinuation: Bool

    public init(character: Character = " ", style: Style = .plain, isContinuation: Bool = false) {
        self.character = character
        self.style = style
        self.isContinuation = isContinuation
    }

    /// 既定スタイルの空白セル。
    public static let empty = Cell()
}
