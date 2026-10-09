/// 端末エミュレータが表示する 1 文字分のます目。
public struct Cell: Hashable, Sendable {
    /// 表示する書記素クラスタ。
    public var character: Character
    /// 見た目。
    public var style: Style
    /// 直前の全角文字が占める、右半分の `Cell` であることを示す。
    ///
    /// - Note: `isContinuation` が `true` の `Cell` は端末デバイスへ書き出さない（直前の全角文字の
    ///   描画によって既に埋まっているため）が、`Renderer` が直前に書き出した `Buffer` と比べるときは、
    ///   ほかの `Cell` と同じように比較される。
    public var isContinuation: Bool

    /// `Cell` を作る。
    ///
    /// - Parameters:
    ///   - character: 表示する書記素クラスタ。
    ///   - style: 見た目。
    ///   - isContinuation: 直前の全角文字が占める、右半分の `Cell` か。
    public init(character: Character = " ", style: Style = .plain, isContinuation: Bool = false) {
        self.character = character
        self.style = style
        self.isContinuation = isContinuation
    }

    /// `Style.plain` の空白の `Cell`。
    public static let empty = Cell()
}
