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

起動から終了までの局面は、`TerminalApp` のメソッドで受け取る。どれもデフォルトの実装があり、書かなければ何もしない。

| 局面 | メソッド |
| --- | --- |
| 起動する | `init()`。端末デバイスを raw モードにする前に呼び出される |
| 起動してから終了するまで | `TerminalApp.task(sender:)`。最初の描画の後に始まり、イベントループを抜けると打ち切られる |
| 一時停止する・再開した | `TerminalApp.willSuspend()`・`TerminalApp.didResume()` |
| 終了した | `TerminalApp.didTerminate(_:)`。端末デバイスを戻した後に、終了した理由（`TerminationReason`）とともに呼び出される |

`TerminalApp.task(sender:)` で受け取った `MessageSender` で値を送ると、`TerminalApp.receive(_:)` に渡り、画面が描き直される。
`ApplicationOptions.frameInterval` を設定しなくてもよい。

```swift
@main
final class Clock: TerminalApp {
    enum Message: Sendable { case tick }

    private var seconds = 0

    var body: some View {
        Text("起動してから \(seconds) 秒")
    }

    func task(sender: MessageSender<Message>) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            sender.send(.tick)
        }
    }

    func receive(_ message: Message) -> EventResult {
        seconds += 1
        return .handled
    }

    func didTerminate(_ reason: TerminationReason) {
        print("\(seconds) 秒で終了しました")
    }
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
