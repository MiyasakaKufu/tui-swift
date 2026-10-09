# TUIKit

ターミナル UI（TUI）アプリを Swift で構築するためのライブラリ。

```
┌─ 特徴 ─────────────┐┌─ 詳細 ───────────────────┐
│> 差分だけ書き出す  ││ 選択中: 差分だけ書き出す │
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
    private var count = 0

    var body: some View {
        VStack(spacing: 1) {
            Text("カウント: \(count)").bold()
            Text("↑↓ で増減、q で終了").dim()
        }
        .padding(1)
        .border(.rounded, title: "Counter")
    }

    func handle(_ event: InputEvent) -> EventResult {
        guard case .key(let key) = event else { return .ignored }
        switch key.key {
        case .up: count += 1
        case .down: count -= 1
        case .character("q"), .escape: return .quit
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

罫線素片や `…` など East Asian Width が Ambiguous の文字は、初期値では `Cell` 1 個分として扱う。
環境変数 `RUNEWIDTH_EASTASIAN` が `1` のときと、`ApplicationOptions.ambiguousWidth` を `.wide` に
したときは `Cell` 2 個分として扱い、`View.border(_:style:title:titleStyle:)` の枠線は `BorderStyle.ascii`（`+-|`）へ切り替わる。

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
