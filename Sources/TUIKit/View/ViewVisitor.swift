/// ``PrimitiveView/visitChildren(_:)`` で、``RenderContext`` のメソッドに `child` 引数として渡しうる ``View`` を受け取る型。
@MainActor
public struct ViewVisitor {
    /// ``PrimitiveView/visitChildren(_:)`` を呼び出された ``View`` の `ViewNode`。
    let node: ViewNode
    /// `ViewVisitor.node` を持つ `ViewGraph`。
    let graph: ViewGraph

    /// `child` の ``View`` と、その ``View`` から ``RenderContext`` のメソッドに `child` 引数として渡されうる ``View`` をたどる。
    ///
    /// - Parameters:
    ///   - child: ``RenderContext`` のメソッドに `child` 引数として渡しうる ``ViewList/Element``。
    ///   - slot: `child` を ``RenderContext`` のメソッドに渡すときの `slot` 引数。
    public func visit(_ child: ViewList.Element, slot: Int) {
        func visitView(_ view: some View) {
            let childNode = graph.node(at: node.path.appending(child, slot: slot), viewType: type(of: view))
            graph.visit(view, node: childNode)
        }
        visitView(child.view)
    }
}
