/// 端末カーソルの形と点滅の有無。
public enum CursorShape: Hashable, Sendable {
    /// 端末の設定どおりの形。
    case `default`
    /// 点滅するブロック。
    case blinkingBlock
    /// 点滅しないブロック。
    case block
    /// 点滅する下線。
    case blinkingUnderline
    /// 点滅しない下線。
    case underline
    /// 点滅する縦棒。
    case blinkingBar
    /// 点滅しない縦棒。
    case bar

    /// `DECSCUSR`（`CSI Ps SP q`）へ渡す番号。
    var parameter: Int {
        switch self {
        case .default: return 0
        case .blinkingBlock: return 1
        case .block: return 2
        case .blinkingUnderline: return 3
        case .underline: return 4
        case .blinkingBar: return 5
        case .bar: return 6
        }
    }
}
