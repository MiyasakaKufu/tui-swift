/// `VStack` などの `content` クロージャで複数のビューを並べるためのビルダ。
@resultBuilder
public enum ViewBuilder {
    /// 1 つのビューを並びにする。
    ///
    /// - Parameters:
    ///   - view: 並べるビュー。
    /// - Returns: そのビュー 1 つだけの並び。
    public static func buildExpression(_ view: any View) -> [any View] {
        [view]
    }

    /// ビューの並びをそのまま受け取る。
    ///
    /// - Parameters:
    ///   - views: 並べるビュー。
    /// - Returns: 受け取った並び。
    public static func buildExpression(_ views: [any View]) -> [any View] {
        views
    }

    /// クロージャに並んだビューを 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 各行のビューの並び。
    /// - Returns: 順に連結した並び。
    public static func buildBlock(_ components: [any View]...) -> [any View] {
        components.flatMap { $0 }
    }

    /// `if` で条件を満たさなかった場合を空の並びにする。
    ///
    /// - Parameters:
    ///   - component: 条件を満たしたときのビューの並び。満たさなければ `nil`。
    /// - Returns: `component`。`nil` なら空の並び。
    public static func buildOptional(_ component: [any View]?) -> [any View] {
        component ?? []
    }

    /// `if` の側のビューを並びにする。
    ///
    /// - Parameters:
    ///   - component: `if` の側のビューの並び。
    /// - Returns: 受け取った並び。
    public static func buildEither(first component: [any View]) -> [any View] {
        component
    }

    /// `else` の側のビューを並びにする。
    ///
    /// - Parameters:
    ///   - component: `else` の側のビューの並び。
    /// - Returns: 受け取った並び。
    public static func buildEither(second component: [any View]) -> [any View] {
        component
    }

    /// `for` で作られたビューを 1 つの並びにまとめる。
    ///
    /// - Parameters:
    ///   - components: 繰り返しごとのビューの並び。
    /// - Returns: 順に連結した並び。
    public static func buildArray(_ components: [[any View]]) -> [any View] {
        components.flatMap { $0 }
    }

    /// `if #available` の中のビューを並びにする。
    ///
    /// - Parameters:
    ///   - component: 利用できる場合のビューの並び。
    /// - Returns: 受け取った並び。
    public static func buildLimitedAvailability(_ component: [any View]) -> [any View] {
        component
    }
}
