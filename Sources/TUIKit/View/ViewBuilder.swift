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
        ViewList([view])
    }

    /// ``View`` の配列を並びにする。
    ///
    /// - Parameters:
    ///   - views: 並べる ``View``。
    /// - Returns: `views` を順に並べた ``ViewList``。
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
    /// - Returns: 順に連結した ``ViewList``。
    public static func buildBlock(_ components: ViewList...) -> ViewList {
        concatenate(components)
    }

    /// `if` で条件を満たさなかった場合を空の並びにする。
    ///
    /// - Parameters:
    ///   - component: 条件を満たしたときの ``ViewList``。満たさなければ `nil`。
    /// - Returns: `component`。`nil` なら空の ``ViewList``。
    public static func buildOptional(_ component: ViewList?) -> ViewList {
        component ?? ViewList([])
    }

    /// `if` の条件を満たしたときの ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たしたときの ``ViewList``。
    /// - Returns: 受け取った ``ViewList``。
    public static func buildEither(first component: ViewList) -> ViewList {
        component
    }

    /// `if` の条件を満たさず `else` に進んだときの ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たさず `else` に進んだときの ``ViewList``。
    /// - Returns: 受け取った ``ViewList``。
    public static func buildEither(second component: ViewList) -> ViewList {
        component
    }

    /// `for` で作られた ``View`` を 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 繰り返しごとの ``ViewList``。
    /// - Returns: 順に連結した ``ViewList``。
    public static func buildArray(_ components: [ViewList]) -> ViewList {
        concatenate(components)
    }

    /// `if #available` の中の ``View`` を並びにする。
    ///
    /// - Parameters:
    ///   - component: 利用できる場合の ``ViewList``。
    /// - Returns: 受け取った ``ViewList``。
    public static func buildLimitedAvailability(_ component: ViewList) -> ViewList {
        component
    }

    /// `lists` の要素を順に連結し、書いた位置を連結した後の順に数え直す。
    ///
    /// - Parameters:
    ///   - lists: 連結する ``ViewList``。
    /// - Returns: 連結した ``ViewList``。
    private static func concatenate(_ lists: [ViewList]) -> ViewList {
        ViewList(lists.flatMap { $0.map(\.view) })
    }
}
