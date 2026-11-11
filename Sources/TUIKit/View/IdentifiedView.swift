/// ``ViewBuilder`` のクロージャで書いた位置ではなく、``View/id(_:)`` の引数で同一性が決まる ``View``。
@MainActor
protocol ExplicitlyIdentified {
    /// 同一性を決める、``View/id(_:)`` の引数。
    var identityKey: AnyHashable { get }
}

/// ``View/id(_:)`` の引数で同一性を決める ``View``。
///
/// ``ViewBuilder`` のクロージャで書いた位置の代わりに、``View/id(_:)`` の引数を使う。``View/id(_:)`` で作る。
public struct IdentifiedView<Content: View, ID: Hashable>: View, ExplicitlyIdentified {
    /// ``IdentifiedView/id`` を付ける ``View``。
    public var content: Content
    /// 同一性を決める、``View/id(_:)`` の引数。
    public var id: ID

    /// `content` と `id` を指定して ``IdentifiedView`` を作る。
    ///
    /// - Parameters:
    ///   - content: `id` を付ける ``View``。
    ///   - id: 同一性を決める、``View/id(_:)`` の引数。
    public init(content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    /// ``IdentifiedView/id`` を付ける ``View``（``IdentifiedView/content``）。
    public var body: Content { content }

    /// 同一性を決める ``IdentifiedView/id`` を `AnyHashable` に包んだもの。
    var identityKey: AnyHashable { AnyHashable(id) }
}

extension View {
    /// ``ViewBuilder`` のクロージャで書いた位置の代わりに、`id` で同一性を決める。
    ///
    /// ``View/id(_:)`` の引数が同じ ``View`` は、書いた位置が変わっても、`Application.draw()` をまたいで同じ ``View`` として扱われる。比べるのは、同じ ``View`` が受け取った ``RenderContext`` のメソッドに、同じ `slot` 引数とともに `child` 引数として渡す ``ViewList/Element`` の ``View`` どうしに限る。
    /// ``View/id(_:)`` の引数が変わると、別の ``View`` として扱われる。
    ///
    /// - Parameters:
    ///   - id: 同一性を決める、`Hashable` に準拠する型のインスタンス。
    /// - Returns: この ``View`` を ``IdentifiedView/content`` にした ``IdentifiedView``。
    /// - Note: ``View/id(_:)`` を呼び出していない ``View`` の同一性は、``RenderContext`` のメソッドに渡された `slot` 引数と書いた位置で決まる。
    ///   前に書いた `if` や `for` の中の ``View`` の数が変わると、後ろの ``View`` の書いた位置が変わり、同一性が変わる。変えたくない ``View`` には ``View/id(_:)`` で `id` を付ける。
    /// - Warning: 同じ ``View`` が受け取った ``RenderContext`` のメソッドに、同じ `slot` 引数とともに `child` 引数として渡す 2 つの ``ViewList/Element`` の ``View`` に、同じ ``View/id(_:)`` の引数を付けない。同じ ``View`` として扱われる。
    public func id<ID: Hashable>(_ id: ID) -> IdentifiedView<Self, ID> {
        IdentifiedView(content: self, id: id)
    }
}
