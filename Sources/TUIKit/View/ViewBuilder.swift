/// ``VStack`` などの `content` クロージャで複数の ``View`` を並べるためのビルダ。
///
/// 並べた ``View`` を、書いた位置とともに ``ViewList`` にまとめる。
@resultBuilder
public enum ViewBuilder {
    /// 1 つの ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - view: 並べる ``View``。
    /// - Returns: `view` 1 つだけの ``ViewList``。
    public static func buildExpression(_ view: any View) -> ViewList {
        ViewList(elements: [ViewList.Element(view: view, position: [])])
    }

    /// ``View`` の配列を並びにする。
    ///
    /// - Parameters:
    ///   - views: 並べる ``View``。
    /// - Returns: 配列の中の位置を書いた位置とした ``ViewList``。
    public static func buildExpression(_ views: [any View]) -> ViewList {
        ViewList(views)
    }

    /// ``ViewList`` をそのまま受け取る。
    ///
    /// `@ViewBuilder` を付けた関数が返した ``ViewList`` を、別の `content` クロージャに並べるときに使う。
    ///
    /// - Parameters:
    ///   - list: 並べる ``ViewList``。
    /// - Returns: 受け取った ``ViewList``。
    public static func buildExpression(_ list: ViewList) -> ViewList {
        list
    }

    /// クロージャに並んだ ``View`` を 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: クロージャに並べた順の、それぞれの ``ViewList``。
    /// - Returns: 順に連結した ``ViewList``。要素の ``View`` の同一性は、クロージャに並べた順番で決まり、前に並べた `if` や `for` の中の ``View`` の数に左右されない。
    public static func buildBlock(_ components: ViewList...) -> ViewList {
        // 並べた順番を足さずに `components.flatMap { $0 }` で平らにつなげたくなるが、そうすると前に並べた `if` の中の `View` の数で後ろの要素の書いた位置がずれ、後ろの `View` の `@State` が初期値に戻る。
        ViewList(elements: components.enumerated().flatMap { $1.prefixed(with: $0) })
    }

    /// `if` で条件を満たさなかった場合を空の並びにする。
    ///
    /// - Parameters:
    ///   - component: 条件を満たしたときの ``ViewList``。満たさなければ `nil`。
    /// - Returns: `component`。`nil` なら空の ``ViewList``。
    public static func buildOptional(_ component: ViewList?) -> ViewList {
        component ?? ViewList(elements: [])
    }

    /// `if` の条件を満たしたときの ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たしたときの ``ViewList``。
    /// - Returns: 要素の ``View`` が、`else` に書いた ``View`` と別の ``View`` として扱われる ``ViewList``。
    public static func buildEither(first component: ViewList) -> ViewList {
        // 分岐を区別せず `component` をそのまま返したくなるが、そうすると `if` 側と `else` 側で `View` の数が違うとき、`else` 側の `View` が、`if` 側の同じ位置にある別の `View` の `@State` を引き継ぐ。
        component.prefixed(with: 0)
    }

    /// `if` の条件を満たさず `else` に進んだときの ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たさず `else` に進んだときの ``ViewList``。
    /// - Returns: 要素の ``View`` が、`if` の条件を満たしたときに書いた ``View`` と別の ``View`` として扱われる ``ViewList``。
    public static func buildEither(second component: ViewList) -> ViewList {
        component.prefixed(with: 1)
    }

    /// `for` で作られた ``View`` を 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 繰り返しごとの ``ViewList``。
    /// - Returns: 順に連結した ``ViewList``。要素の ``View`` の同一性は、何回目かで決まる。
    public static func buildArray(_ components: [ViewList]) -> ViewList {
        // 何回目かを足さずに平らにつなげたくなるが、そうすると繰り返しの中の `if` の中の `View` の数で、後の回の要素の書いた位置がずれ、後の回の `View` の `@State` が初期値に戻る。
        ViewList(elements: components.enumerated().flatMap { $1.prefixed(with: $0) })
    }

    /// `if #available` の中の ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: 利用できる場合の ``ViewList``。
    /// - Returns: 受け取った ``ViewList``。
    public static func buildLimitedAvailability(_ component: ViewList) -> ViewList {
        component
    }
}
