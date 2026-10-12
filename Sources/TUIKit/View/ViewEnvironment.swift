/// `ViewGraph` を使う側が、``State`` などを結び付けるときと描画するときに ``View`` へ渡すもの。
@MainActor
struct ViewEnvironment {
    /// フォーカスを保持する `FocusProviding`。無ければ、どの ``View`` もフォーカスを持たない。
    var focus: (any FocusProviding)?
}
