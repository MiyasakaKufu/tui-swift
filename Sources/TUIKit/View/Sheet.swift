/// ``SheetView/isPresented`` が `true` の間、画面の中央に `content:` の ``View`` を表示し、後ろの ``SheetView/content`` へ ``InputEvent`` を渡さない ``View``。``View/sheet(isPresented:content:)`` で作る。
///
/// - Note: 画面の中央に表示した ``View`` が後から描かれる ``View`` に隠れないよう、``SheetView`` を、``Application`` が最初にメソッドを呼び出す ``View`` にする（``Component/body`` が ``View/sheet(isPresented:content:)`` の戻り値を返すようにする）。
public struct SheetView<Content: View, SheetContent: View>: PrimitiveView {
    /// 後ろに描く ``View``。
    public var content: Content
    /// `content:` の ``View`` を表示するかを持つプロパティの ``Binding``。
    public var isPresented: Binding<Bool>
    /// 画面の中央に表示する ``View`` を返すクロージャ。
    let makeSheet: @MainActor () -> SheetContent

    /// ``SheetView`` を作る。
    ///
    /// - Parameters:
    ///   - content: 後ろに描く ``View``。
    ///   - isPresented: 画面の中央に表示するかを持つプロパティの ``Binding``。
    ///   - makeSheet: 画面の中央に表示する ``View`` を返すクロージャ。
    init(content: Content, isPresented: Binding<Bool>, makeSheet: @escaping @MainActor () -> SheetContent) {
        self.content = content
        self.isPresented = isPresented
        self.makeSheet = makeSheet
    }

    /// ``SheetView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値を返す。
    ///
    /// - Parameters:
    ///   - proposal: ``RenderContext/sizeThatFits(of:index:proposal:)`` の `proposal` 引数に渡された ``Size``。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``SheetView/content`` の ``View/sizeThatFits(_:context:)`` の戻り値。
    public func sizeThatFits(_ proposal: Size, context: RenderContext) -> Size {
        context.sizeThatFits(of: content, index: 0, proposal: proposal)
    }

    /// ``SheetView/content`` の ``LayoutTraits`` を返す。
    ///
    /// - Parameters:
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    /// - Returns: ``SheetView/content`` の ``View/layoutTraits(context:)`` の戻り値。
    public func layoutTraits(context: RenderContext) -> LayoutTraits {
        context.layoutTraits(of: content, index: 0)
    }

    /// ``SheetView/content`` を描画し、``SheetView/isPresented`` が `true` なら画面の中央へ `content:` の ``View`` を重ねる。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の ``Buffer``。
    ///   - rect: ``SheetView/content`` を描画する矩形。
    ///   - context: 別の ``View`` のメソッドを呼び出すための ``RenderContext``。
    public func render(into buffer: inout Buffer, rect: Rect, context: RenderContext) {
        context.render(content, index: 0, into: &buffer, rect: rect)
        guard isPresented.wrappedValue, !context.screen.isEmpty else { return }
        let sheet = makeSheet()
        let sheetRect = OverlayLayout.childRect(
            for: sheet,
            index: 1,
            in: context.screen,
            horizontal: .center,
            vertical: .center,
            context: context
        )
        context.render(sheet, index: 1, into: &buffer, rect: sheetRect)
    }

    /// ``SheetView/content`` を `index:` 引数を 0 として、``SheetView/isPresented`` が `true` なら `content:` の ``View`` を `index:` 引数を 1 として、`visitor` に渡す。
    ///
    /// - Parameters:
    ///   - visitor: 渡しうる ``View`` を受け取る ``ViewVisitor``。
    public func visitChildren(_ visitor: ViewVisitor) {
        visitor.visit(content, index: 0)
        if isPresented.wrappedValue {
            visitor.visit(makeSheet(), index: 1)
        }
    }
}

/// ``View/sheet(isPresented:content:)`` で作った ``View`` が、たどったときに `FocusController` へ示すもの。
@MainActor
protocol SheetPresentingView {
    /// `content:` の ``View`` を表示していれば `true`。
    var isPresentingSheet: Bool { get }

    /// 後ろに描く ``View`` の `ViewPath` を返す。
    ///
    /// - Parameters:
    ///   - path: この ``View`` の `ViewPath`。
    /// - Returns: 後ろに描く ``View`` の `ViewPath`。
    func pathBehindSheet(from path: ViewPath) -> ViewPath
}

extension SheetView: SheetPresentingView {
    /// `content:` の ``View`` を表示していれば `true`。
    var isPresentingSheet: Bool { isPresented.wrappedValue }

    /// ``SheetView/content`` の `ViewPath` を返す。
    ///
    /// - Parameters:
    ///   - path: この ``SheetView`` の `ViewPath`。
    /// - Returns: ``SheetView/content`` の `ViewPath`。
    func pathBehindSheet(from path: ViewPath) -> ViewPath {
        path.appending(content, index: 0)
    }
}

extension View {
    /// `isPresented` が `true` の間、画面の中央に `content` の ``View`` を表示し、この ``View`` の内側へ ``InputEvent`` を渡さない。
    ///
    /// 表示している間、この ``View`` の内側の ``View`` は `.key`・`.mouse`・`.paste` を受け取らず、Tab によるフォーカスの移動先にも含まれない。表示すると、`content` の ``View`` の内側で、たどった順で先頭のフォーカスを受け取る ``View`` へフォーカスが移る。閉じると、表示する前にフォーカスを持っていた ``View`` へ戻る。
    ///
    /// - Parameters:
    ///   - isPresented: 表示するかを持つプロパティの ``Binding``。
    ///   - content: 画面の中央に表示する ``View`` を返すクロージャ。`isPresented` が `true` の間だけ呼び出す。
    /// - Returns: `content` を重ねる ``SheetView``。
    /// - Note: 表示している間も、どの ``View`` も処理しなかった `.key`・`.paste` は ``Component/handle(_:)`` へ渡る。
    public func sheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        content: @escaping @MainActor () -> SheetContent
    ) -> SheetView<Self, SheetContent> {
        SheetView(content: self, isPresented: isPresented, makeSheet: content)
    }
}
