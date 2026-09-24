/// 位置ではなく鍵で同一性が決まるビュー。
@MainActor
protocol ExplicitlyIdentified {
    /// 同一性を決める鍵。
    var identityKey: AnyHashable { get }
}

/// 内容に鍵を付け、親の中での位置の代わりに鍵で同一性を決めるビュー。
///
/// `id(_:)` で作る。
public struct IdentifiedView<Content: View, ID: Hashable>: View, ExplicitlyIdentified {
    /// 鍵を付ける内容。
    public var content: Content
    /// 同一性を決める鍵。
    public var id: ID

    /// 内容と鍵を指定して作る。
    ///
    /// - Parameters:
    ///   - content: 鍵を付ける内容。
    ///   - id: 同一性を決める鍵。
    public init(content: Content, id: ID) {
        self.content = content
        self.id = id
    }

    /// 鍵を付ける内容。
    public var body: Content { content }

    /// 同一性を決める鍵。
    var identityKey: AnyHashable { AnyHashable(id) }
}

extension View {
    /// 親の中での位置の代わりに、`id` で同一性を決める。
    ///
    /// 同じ親の下で同じ鍵を持つビューは、並びの中で位置が変わっても、フレームをまたいで同じビューとして扱われる。
    /// 鍵が変わると、別のビューとして扱われる。
    ///
    /// - Parameters:
    ///   - id: 同一性を決める鍵。
    /// - Returns: 鍵を付けたビュー。
    /// - Note: 鍵を付けないビューの同一性は、親の中での位置で決まる。`ViewBuilder` の `if` で
    ///   前にあるビューを出し分けると、後ろのビューの位置がずれ、同一性が変わる。変えたくないビューには鍵を付ける。
    /// - Warning: 同じ親の下で、2 つのビューに同じ鍵を付けない。同じビューとして扱われる。
    public func id<ID: Hashable>(_ id: ID) -> IdentifiedView<Self, ID> {
        IdentifiedView(content: self, id: id)
    }
}
