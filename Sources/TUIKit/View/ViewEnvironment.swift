/// `ViewGraph` が、``State`` などを結び付けるときと描画するときに ``View`` へ渡すもの。値は `ApplicationContext` が設定する。
@MainActor
struct ViewEnvironment {
    /// フォーカスを保持する `FocusProviding`。無ければ、どの ``View`` もフォーカスを持たない。
    var focus: (any FocusProviding)?
    /// ``RenderContext/theme`` が返す ``Theme``。
    var theme: Theme = .standard
}
