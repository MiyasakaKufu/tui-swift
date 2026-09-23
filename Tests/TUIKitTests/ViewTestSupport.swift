@testable import TUIKit

@MainActor
extension View {
    /// ルートのビューとして、`Application` と同じ文脈で `rect` へ描画する。
    ///
    /// - Parameters:
    ///   - buffer: 描画先のバッファ。画面全体として扱う。
    ///   - rect: 描画する矩形。
    func renderAsRoot(into buffer: inout Buffer, rect: Rect) {
        let context = RenderContext(screen: buffer.bounds)
        render(into: &buffer, rect: rect, context: context)
    }

    /// ルートのビューとして測ったときの、希望するサイズを返す。
    ///
    /// - Parameters:
    ///   - proposal: 提案する領域の大きさ。画面全体の大きさとしても扱う。
    /// - Returns: 希望するサイズ。
    func sizeThatFitsAsRoot(_ proposal: Size) -> Size {
        let context = RenderContext(screen: Rect(origin: Point(x: 0, y: 0), size: proposal))
        return sizeThatFits(proposal, context: context)
    }
}
