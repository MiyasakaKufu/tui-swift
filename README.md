# TUIKit

ターミナル UI（TUI）アプリを Swift で構築するためのライブラリ。

```
┌─ 特徴 ─────────────┐┌─ 詳細 ───────────────────┐
│> 差分レンダリング  ││ 選択中: 差分レンダリング │
│  全角文字の幅計算  ││ 進捗                     │
│  キー入力の解析    ││ ███████░░░░░░░░░░  38%   │
└────────────────────┘└──────────────────────────┘
```

## 使い方

`Package.swift` に追加する。

```swift
dependencies: [
    .package(url: "https://github.com/MiyasakaKufu/tui-swift.git", branch: "main")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: [
        .product(name: "TUIKit", package: "tui-swift")
    ])
]
```

最小限の TUIKit アプリは次のようになる。`TerminalApp` に準拠する型に `@main` を付けると、そのままエントリポイントになる。

```swift
// Sources/MyApp/Counter.swift
import TUIKit

@main
final class Counter: TerminalApp {
    private(set) var isFinished = false
    private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("カウント: \(count)").bold()
            Text("↑↓ で増減、q で終了").foregroundStyle(.secondary)
        }
        .padding(1)
        .border(.rounded, title: "Counter")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let key) = event else { return .ignored }
        switch key.key {
        case .up: count += 1
        case .down: count -= 1
        case .character("q"), .escape: isFinished = true
        default: return .ignored
        }
        return .handled
    }
}
```

`@main` はファイル名 `main.swift` では使えないため、ファイル名は型名に合わせる。

`Application` の起動時に渡す `ApplicationOptions` は、`TerminalApp.options` が返す。マウス（`ApplicationOptions.mouseTracking`）と
フォーカス通知（`ApplicationOptions.reportsFocus`）は、初期値では無効になっている。

```swift
static var options: ApplicationOptions {
    ApplicationOptions(mouseTracking: .buttons, windowTitle: "MyApp")
}
```

配色は、SwiftUI と同じく `View` の拡張メソッドで決め、その `View` の内側の `View` へ伝わる。`TerminalApp.body` が返す `View` に付ければ、
TUIKit アプリ全体の配色を一箇所で決められる。文字色は `View.foregroundStyle(_:_:)`（プライマリレベルとセカンダリレベル）、
`ProgressBar` の進んだ部分と `ListView` の選択行の色は `View.tint(_:)`、背景色は `View.background(_:)` で決める。
何も決めなければ、SGR 39 / 49 で指す、端末エミュレータで選んである文字色と背景色で描く。

```swift
var body: some View {
    VStack {
        Text("名前")
        Text("補足").foregroundStyle(.secondary)
        ProgressBar(value: 0.4)
    }
    .tint(.cyan)
}
```

罫線素片や `…` など East Asian Width が Ambiguous の文字は、初期値では `Cell` 1 個分として扱う。
環境変数 `RUNEWIDTH_EASTASIAN` が `1` のときと、`ApplicationOptions.ambiguousWidth` を `.wide` に
したときは `Cell` 2 個分として扱い、`View.border(_:color:title:)` の枠線は `BorderStyle.ascii`（`+-|`）へ切り替わる。

同梱のデモは次で起動する。

```
swift run tui-demo
```

## 動作環境

- Swift 6.0 以降
- macOS 15 以降、または Linux
- `hasPrefix(ANSI.csi)` か `hasPrefix(ANSI.osc)` が `true` の `String` を解釈する端末エミュレータ

## 開発

```
swift test
```

DocC・コメント・コミットログの書き方は `CONTRIBUTING.md` にまとめている。

## ライセンス

MIT License（`LICENSE` を参照）。
