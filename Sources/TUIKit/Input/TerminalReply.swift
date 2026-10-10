/// 問い合わせに対して端末エミュレータが返した応答。
///
/// `InputEvent` としては届かない。`InputParser.takeReplies()` で取り出す。
public enum TerminalReply: Hashable, Sendable {
    /// kitty keyboard protocol の対応状況（`CSI ? <flags> u`）。
    ///
    /// 応答が返ること自体が対応している証拠で、`flags` は今有効になっている機能を表す。
    case keyboardProtocol(flags: Int)
    /// 端末エミュレータの種別（`CSI ? <params> c`）。
    case deviceAttributes
}
