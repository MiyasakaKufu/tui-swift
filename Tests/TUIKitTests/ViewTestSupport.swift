@testable import TUIKit

@MainActor
extension View {
    /// `RenderContext.init(screen:ambiguousWidth:)` で作った `RenderContext` を渡して、`View.render(into:rect:context:)` を呼び出す。
    ///
    /// - Parameters:
    ///   - buffer: 描画先の `Buffer`。画面全体として扱い、`Cell` の数は `Buffer.ambiguousWidth` で数える。
    ///   - rect: 描画する矩形。
    /// - Note: この `View` 自身の `State` は、`Application` と違って記憶域に結び付かず、初期値のままになる。
    func renderAsRoot(into buffer: inout Buffer, rect: Rect) {
        let context = RenderContext(screen: buffer.bounds, ambiguousWidth: buffer.ambiguousWidth)
        render(into: &buffer, rect: rect, context: context)
    }

    /// `RenderContext.init(screen:ambiguousWidth:)` で作った `RenderContext` を渡して `View.sizeThatFits(_:context:)` を呼び出し、その戻り値を返す。
    ///
    /// - Parameters:
    ///   - proposal: `View.sizeThatFits(_:context:)` の `proposal` 引数に渡す `Size`。画面全体の大きさとしても扱う。
    /// - Returns: `View.sizeThatFits(_:context:)` の戻り値。
    func sizeThatFitsAsRoot(_ proposal: Size) -> Size {
        let context = RenderContext(screen: Rect(origin: Point(x: 0, y: 0), size: proposal))
        return sizeThatFits(proposal, context: context)
    }

    /// `RenderContext.init(screen:ambiguousWidth:)` で作った `RenderContext` を渡して `View.layoutTraits(context:)` を呼び出し、その戻り値を返す。
    ///
    /// - Returns: `View.layoutTraits(context:)` の戻り値の `LayoutTraits`。
    func layoutTraitsAsRoot() -> LayoutTraits {
        layoutTraits(context: RenderContext(screen: .zero))
    }
}
