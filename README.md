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

`View.disabled(_:)` に `true` を渡すと、その `View` と内側の `View` は、キー・マウス・Tab によるフォーカスの移動の対象から外れる。
外側で `true` を渡していれば、内側で `false` を渡しても外れたままになる。`TextField`・`ListView` は、文字に `TextAttributes.dim`（SGR 2）を足して描かれる。

```swift
VStack {
    TextField(text: $name, state: nameState)
    TextField(text: $note, state: noteState)
}
.disabled(isSending)
```

ファイルの読み込みや通信のように時間のかかる処理は、`TerminalApp.task(sender:)` の中で行う。`Application` は最初の描画の後に
`Task` の中でこのメソッドを呼び出し、イベントループを抜けるとその `Task` を打ち切る。結果は引数の `MessageSender` で送り、
`TerminalApp.receive(_:)` で受け取る。送った値を `TerminalApp.receive(_:)` へ渡した後に描き直すので、`ApplicationOptions.frameInterval` を
設定して終わったかを確かめに行く必要はない。

```swift
enum Message: Sendable {
    case loaded([String])
}

private var items: [String] = []

func task(sender: MessageSender<Message>) async {
    let loaded = await fetchItems()
    sender.send(.loaded(loaded))
}

func receive(_ message: Message) -> EventResult {
    switch message {
    case .loaded(let loaded):
        items = loaded
        return .handled
    }
}
```

`TerminalApp.task(sender:)` の中でプロパティへ代入しただけでは描き直されないので、画面に出す値は `MessageSender` で送る。
キーを押したときなどに処理を始めるなら、`TerminalApp.task(sender:)` の中で `AsyncStream` を読み続け、`TerminalApp.handle(_:)` からそこへ依頼を積む。
`Task` を `TerminalApp.handle(_:)` から作ると、`Application` はその `Task` を打ち切れない。

```swift
private let (requests, requestContinuation) = AsyncStream<String>.makeStream()
private var query = ""

func task(sender: MessageSender<Message>) async {
    for await request in requests {
        sender.send(.loaded(await search(request)))
    }
}

func handle(_ event: InputEvent) -> EventResult {
    guard case .key(let key) = event, key.key == .enter else { return .ignored }
    requestContinuation.yield(query)
    return .handled
}
```

`Application.run()` は、端末デバイスを元に戻した後、`TerminalApp.task(sender:)` の `Task` が終わるのを待ってから戻る。打ち切りに応じない処理を書くと、
プロセスが終わらない。

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
