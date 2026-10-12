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

/// `ApplicationContext` で `View` を描き、`InputEvent` を渡す。`Application` と同じく、`InputEvent` を 1 つ渡すたびに描き直す。
@MainActor
final class FocusHarness<V: View> {
    /// フォーカスを保持する `ApplicationContext`。
    let context = ApplicationContext()
    /// 最後に描いた `Buffer`。
    private(set) var buffer: Buffer
    /// `ApplicationContext.draw(_:into:ambiguousWidth:present:)` が `present` に `Buffer` を渡した回数。
    private(set) var presentCount = 0
    /// 描くたびに呼び出し、`Application` が最初にメソッドを呼び出す `View` を返すクロージャ。
    private let makeView: () -> V

    /// `makeView` が返す `View` を 1 回描いて作る。
    ///
    /// - Parameters:
    ///   - size: 画面の大きさ。
    ///   - makeView: 描くたびに呼び出し、`Application` が最初にメソッドを呼び出す `View` を返すクロージャ。
    init(size: Size, _ makeView: @escaping () -> V) {
        self.buffer = Buffer(size: size)
        self.makeView = makeView
        draw()
    }

    /// `Application.draw()` の 1 回分を描く。
    func draw() {
        context.draw(makeView, into: &buffer, ambiguousWidth: buffer.ambiguousWidth) { _ in
            presentCount += 1
        }
    }

    /// `key` を渡してから描く。
    ///
    /// - Parameters:
    ///   - key: 渡すキー。
    ///   - modifiers: 同時に押されていた修飾キー。
    /// - Returns: `ApplicationContext.deliver(_:)` の戻り値。
    @discardableResult
    func press(_ key: Key, modifiers: KeyModifiers = []) -> EventResult? {
        let result = context.deliver(KeyEvent(key, modifiers: modifiers))
        draw()
        return result
    }

    /// `point` を左ボタンで押してから描く。
    ///
    /// - Parameters:
    ///   - point: 押す位置。
    ///   - action: 操作の種類。
    /// - Returns: `View` が処理したら `true`。
    @discardableResult
    func click(at point: Point, action: MouseAction = .press) -> Bool {
        let handled = context.deliver(MouseEvent(position: point, button: .left, action: action))
        draw()
        return handled
    }

    /// `text` を貼り付けてから描く。
    ///
    /// - Parameters:
    ///   - text: 貼り付ける文字列。
    /// - Returns: `View` が処理したら `true`。
    @discardableResult
    func paste(_ text: String) -> Bool {
        let handled = context.deliverPaste(.paste(text))
        draw()
        return handled
    }

    /// `Buffer` の `row` 行目の文字列。
    ///
    /// - Parameters:
    ///   - row: 行の番号。
    /// - Returns: `row` 行目の文字列。
    func line(_ row: Int) -> String {
        buffer.text(ofRow: row)
    }
}
