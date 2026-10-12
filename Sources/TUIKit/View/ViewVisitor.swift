/// ``PrimitiveView/visitChildren(_:)`` で、``RenderContext`` のメソッドに `child` 引数として渡しうる ``View`` を受け取る型。
@MainActor
public struct ViewVisitor {
    /// ``PrimitiveView/visitChildren(_:)`` を呼び出された ``View`` の `ViewNode`。
    let node: ViewNode
    /// `ViewVisitor.node` を持つ `ViewGraph`。
    let graph: ViewGraph

    /// `child` と、`child` から ``RenderContext`` のメソッドに `child` 引数として渡されうる ``View`` をたどる。
    ///
    /// - Parameters:
    ///   - child: ``RenderContext`` のメソッドに `child` 引数として渡しうる ``View``。
    ///   - index: `child` を ``RenderContext`` のメソッドに渡すときの `index:` 引数。
    public func visit(_ child: some View, index: Int) {
        let childNode = graph.node(at: node.path.appending(child, index: index), viewType: type(of: child))
        graph.visit(child, node: childNode)
    }
}
