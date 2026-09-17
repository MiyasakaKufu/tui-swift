/// `VStack` などの `content` クロージャで複数のビューを並べるためのビルダ。
@resultBuilder
public enum ViewBuilder {
    public static func buildExpression(_ view: any View) -> [any View] {
        [view]
    }

    public static func buildExpression(_ views: [any View]) -> [any View] {
        views
    }

    public static func buildBlock(_ components: [any View]...) -> [any View] {
        components.flatMap { $0 }
    }

    public static func buildOptional(_ component: [any View]?) -> [any View] {
        component ?? []
    }

    public static func buildEither(first component: [any View]) -> [any View] {
        component
    }

    public static func buildEither(second component: [any View]) -> [any View] {
        component
    }

    public static func buildArray(_ components: [[any View]]) -> [any View] {
        components.flatMap { $0 }
    }

    public static func buildLimitedAvailability(_ component: [any View]) -> [any View] {
        component
    }
}
