/// ``DisabledView/isDisabled`` が `true` の間、``DisabledView/content`` と、その内側の ``View`` を、`.key`・`.mouse` と Tab によるフォーカスの移動の対象から外す ``View``。
///
/// ``View/disabled(_:)`` で作る。
public struct DisabledView<Content: View>: PrimitiveView {
    /// `.key`・`.mouse` と Tab によるフォーカスの移動の対象から外す範囲の ``View``。
    public var content: Content
    /// ``DisabledView/content`` を、`.key`・`.mouse` と Tab によるフォーカスの移動の対象から外すなら `true`。
    public var isDisabled: Bool

    /// ``DisabledView`` を作る。
    ///
    /// - Parameters:
    ///   - content: `.key`・`.mouse` と Tab によるフォーカスの移動の対象から外す範囲の ``View``。
    ///   - isDisabled: `content` を、`.key`・`.mouse` と Tab によるフォーカスの移動の対象から外すなら `true`。
    init(content: Content, isDisabled: Bool) {
        self.content = content
        self.isDisabled = isDisabled
    }

    /// ``DisabledView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``DisabledView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// ``DisabledView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値をそのまま返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``DisabledView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// ``DisabledView/content`` を描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: 描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        var contentContext = context
        // `isEnabled = !isDisabled` と書きたくなるが、外側の `View.disabled(_:)` に `true` を渡していても、内側の `false` で操作できる見た目に戻ってしまう。
        if isDisabled {
            contentContext.isEnabled = false
        }
        contentContext.render(content, index: 0, into: &buffer, rect: rect)
    }

    /// ``DisabledView/content`` を、`index:` 引数を 0 として `visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(content, index: 0)
    }
}

/// ``View/disabled(_:)`` で作った ``View`` が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol DisablingView {
    /// 内側の ``View`` を `.key`・`.mouse` と Tab によるフォーカスの移動の対象から外すなら `true`。
    var disablesContent: Bool { get }
}

extension DisabledView: DisablingView {
    /// ``DisabledView/content`` を `.key`・`.mouse` と Tab によるフォーカスの移動の対象から外すなら `true`。
    var disablesContent: Bool { isDisabled }
}

extension View {
    /// `disabled` が `true` なら、この ``View`` と、その内側の ``View`` を、`.key`・`.mouse` と Tab によるフォーカスの移動の対象から外す。
    ///
    /// ```swift
    /// VStack {
    ///     TextField(text: $name, state: nameState)
    ///     TextField(text: $note, state: noteState)
    /// }
    /// .disabled(isSending)
    /// ```
    ///
    /// - Parameters:
    ///   - disabled: この ``View`` と、その内側の ``View`` を、`.key`・`.mouse` と Tab によるフォーカスの移動の対象から外すなら `true`。
    /// - Returns: この ``View`` を ``DisabledView/content`` にした ``DisabledView``。
    /// - Note: 外側の ``View/disabled(_:)`` に `true` を渡していれば、内側で `false` を渡しても対象から外れたままになる。
    /// - Note: 対象から外れた ``TextField``・``ListView`` は、文字に ``TextAttributes/dim`` を足した ``Style`` で描かれる。
    /// - Note: フォーカスを持つ ``View`` が対象から外れると、外れた ``View`` をたどった最初の `Application.draw()` の 1 回で、描画より前に、たどった順で先頭の、対象から外れていないフォーカスを受け取る ``View`` へフォーカスが移る。そうした ``View`` が無ければ、どの ``View`` もフォーカスを持たず、対象に戻ったときに、たどった順で先頭のフォーカスを受け取る ``View`` へフォーカスが移る（``FocusState`` を付けたプロパティへの `nil` の代入でフォーカスを外した後を除く）。外れる前にフォーカスを持っていた ``View`` へ戻すには、``FocusState`` を付けたプロパティへ代入する。
    /// - Note: 対象から外れた ``View`` が ``Buffer`` へ書き込んだ矩形の中の `.mouse` は、その下に書き込んだ ``View`` へも渡らない。
    /// - Note: 対象から外れた ``View`` へ ``FocusState`` を付けたプロパティへの代入でフォーカスを移そうとすると、``FocusState`` のほかの代入と同じく保留し、次の `Application.draw()` の 1 回で 1 回だけ試みる。`disabled` 引数に渡す値を `false` に変えるのと同じクロージャの中で代入すれば、その 1 回でフォーカスが移る。
    /// - Note: どの ``View`` も処理しなかった `.key`・`.paste` は、``TerminalApp/handle(_:)`` へ渡る。
    public func disabled(_ disabled: Bool) -> DisabledView<Self> {
        DisabledView(content: self, isDisabled: disabled)
    }
}
