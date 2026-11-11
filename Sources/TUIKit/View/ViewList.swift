/// ``ViewBuilder`` が作る、``View`` の並び。
///
/// 要素ごとに、``ViewBuilder`` のクロージャでその ``View`` を書いた位置を持つ。書いた位置は、`if` や `for` の中の ``View`` も含めて、クロージャに書いた ``View`` を順に数えた番号。
/// 要素を ``RenderContext/render(_:slot:into:rect:)`` などに渡すと、``View`` の同一性は、書いた位置と `slot` 引数で決まる。
///
/// - Note: 前に書いた `if` の中の ``View`` が現れたり消えたりすると、後ろの ``View`` の書いた位置が変わり、別の ``View`` として扱われる。変えたくない ``View`` には ``View/id(_:)`` で引数を渡す。
public struct ViewList: RandomAccessCollection {
    /// ``ViewList`` の要素 1 つ分。
    ///
    /// ``RenderContext/sizeThatFits(of:slot:proposal:)``・``RenderContext/layoutTraits(of:slot:)``・``RenderContext/render(_:slot:into:rect:)``・``ViewVisitor/visit(_:slot:)`` に渡す。
    public struct Element {
        /// 要素の ``View``。
        let view: any View
        /// ``ViewBuilder`` のクロージャで `ViewList.Element.view` を書いた位置。外側から順に並べた番号。
        let position: [Int]

        /// `view` と書いた位置から要素を作る。
        ///
        /// - Parameters:
        ///   - view: 要素の ``View``。
        ///   - position: ``ViewBuilder`` のクロージャで `view` を書いた位置。
        init(view: any View, position: [Int]) {
            self.view = view
            self.position = position
        }

        // `public` にしたくなるが、そうすると TUIKit の外で `View` ごとに書いた位置が空の要素を作り、同じ `slot` 引数で渡せてしまう。別々の `View` が同じ `ViewPath` になり、`ViewNode` と `@State` を共有する。
        /// ``View`` を 1 つだけ受け取るプロパティの ``View`` を、書いた位置が空の要素にする。
        ///
        /// - Parameters:
        ///   - view: 要素の ``View``。
        init(_ view: some View) {
            self.init(view: view, position: [])
        }
    }

    /// 並びの要素。
    private var elements: [Element]

    /// 要素の配列から ``ViewList`` を作る。
    ///
    /// - Parameters:
    ///   - elements: 並びの要素。
    init(elements: [Element]) {
        self.elements = elements
    }

    /// ``View`` の配列から ``ViewList`` を作る。
    ///
    /// - Parameters:
    ///   - views: 並べる ``View``。配列の中の位置を、書いた位置として使う。
    /// - Note: 配列の途中の ``View`` を取り除くと、後ろの ``View`` の同一性が変わる。変えたくない ``View`` には ``View/id(_:)`` で引数を渡す。
    public init(_ views: [any View]) {
        self.elements = views.enumerated().map { Element(view: $1, position: [$0]) }
    }

    /// 先頭の要素の位置。
    public var startIndex: Int { elements.startIndex }

    /// 末尾の要素の次の位置。
    public var endIndex: Int { elements.endIndex }

    /// `position` 番目の要素にアクセスする。
    ///
    /// - Parameters:
    ///   - position: 要素の位置。`startIndex` 以上 `endIndex` 未満。
    public subscript(position: Int) -> Element {
        elements[position]
    }

    /// すべての要素の書いた位置の先頭に `number` を足した ``ViewList`` を返す。
    ///
    /// - Parameters:
    ///   - number: 書いた位置の先頭に足す番号。
    /// - Returns: 要素の ``View`` と順番はこの ``ViewList`` と同じで、書いた位置の先頭に `number` を足した ``ViewList``。
    func prefixed(with number: Int) -> ViewList {
        ViewList(elements: elements.map { Element(view: $0.view, position: [number] + $0.position) })
    }
}
