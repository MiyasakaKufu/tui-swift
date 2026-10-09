/// `VStack` などの `content` クロージャで複数の `View` を並べるためのビルダ。
@resultBuilder
public enum ViewBuilder {
    /// 1 つの `View` を並びにする。
    ///
    /// - Parameters:
    ///   - view: 並べる `View`。
    /// - Returns: `view` 1 つだけの並び。
    public static func buildExpression(_ view: any View) -> [any View] {
        [view]
    }

    /// `View` の並びをそのまま受け取る。
    ///
    /// - Parameters:
    ///   - views: 並べる `View`。
    /// - Returns: 受け取った並び。
    public static func buildExpression(_ views: [any View]) -> [any View] {
        views
    }

    /// クロージャに並んだ `View` を 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 各行の `View` の並び。
    /// - Returns: 順に連結した並び。
    public static func buildBlock(_ components: [any View]...) -> [any View] {
        components.flatMap { $0 }
    }

    /// `if` で条件を満たさなかった場合を空の並びにする。
    ///
    /// - Parameters:
    ///   - component: 条件を満たしたときの `View` の並び。満たさなければ `nil`。
    /// - Returns: `component`。`nil` なら空の並び。
    public static func buildOptional(_ component: [any View]?) -> [any View] {
        component ?? []
    }

    /// `if` の条件を満たしたときの `View` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たしたときの `View` の並び。
    /// - Returns: 受け取った並び。
    public static func buildEither(first component: [any View]) -> [any View] {
        component
    }

    /// `if` の条件を満たさず `else` に進んだときの `View` を並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の条件を満たさず `else` に進んだときの `View` の並び。
    /// - Returns: 受け取った並び。
    public static func buildEither(second component: [any View]) -> [any View] {
        component
    }

    /// `for` で作られた `View` を 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 繰り返しごとの `View` の並び。
    /// - Returns: 順に連結した並び。
    public static func buildArray(_ components: [[any View]]) -> [any View] {
        components.flatMap { $0 }
    }

    /// `if #available` の中の `View` を並びにする。
    ///
    /// - Parameters:
    ///   - component: 利用できる場合の `View` の並び。
    /// - Returns: 受け取った並び。
    public static func buildLimitedAvailability(_ component: [any View]) -> [any View] {
        component
    }
}
