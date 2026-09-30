# TUIKit

Swift で書かれた、依存ライブラリなしのターミナル UI（TUI）ライブラリ。
macOS と Linux で動作し、標準ライブラリと POSIX API だけを使う。

```
┌─ 機能一覧 ─────────┐┌─ 詳細 ────────────────┐
│> 差分レンダリング  ││ 選択中: 差分レンダリング   │
│  全角文字の幅計算  ││ 進捗                    │
│  キー入力の解析    ││ ███████░░░░░░░░░░  38%  │
└────────────────┘└──────────────────────┘
```

## 特徴

- **差分レンダリング** — 直前に書き出した `Buffer` と比べ、変わった `Cell` だけを端末デバイスへ
  書き出すため、ちらつかず、大きな画面でも出力量が小さい。
- **全角文字と絵文字に対応** — East Asian Width と結合文字を考慮して横方向の長さを計算し、
  全角文字が `Cell` の境界で割れないように `Buffer` へ書き込む。曖昧幅の文字は `Cell` 1 個分と 2 個分から選べる。
  `TextField` は国旗や ZWJ で結合した絵文字を書記素クラスタ単位で 1 文字として扱う。
- **タブの展開** — タブは横方向の長さを計算する前に次のタブストップまでの空白へ展開する。
  タブ幅は、指定しなければ `Cell` 4 個分で、`Text(_:tabSize:)` や `.tabStops(every:)` で変えられる。
- **宣言的なレイアウト** — `VStack` / `HStack` / `Spacer` / `border` などを組み合わせて画面を記述する。
- **`View` の重ね描き** — `ZStack` で同じ領域へ `View` を重ね、`.overlay` でレイアウトを変えずに上へ足す。
  `.screenOverlay` は画面全体を基準に置くので、`View` をどれだけ入れ子にしていても中央にダイアログを出せる。
- **入力の解析** — 矢印キー、ファンクションキー、修飾キー、マウス（SGR 1006）、
  ブラケットペーストを解釈する。分割して届いたシーケンスも正しく扱う。
  端末エミュレータが対応していれば kitty keyboard protocol を使い、Ctrl+I と Tab のように
  従来は同じバイト列だったキーを区別する。
- **IME への対応** — `TextField` は `View.render(into:rect:context:)` のたびに、端末エミュレータの
  カーソルを置く位置を `TextFieldState.renderedCursorPoint` へ記録する。`Component.cursorPosition`
  でそれを返すと、変換中の文字と変換候補が `TextField` の位置に出る。
- **クリップボードへのコピー** — OSC 52 で文字列を端末エミュレータのクリップボードへ渡す
  （`Terminal.copyToClipboard(_:)`）。SSH 越しでも手元の端末エミュレータへ届く。
  OSC 52 を拒否するよう設定した端末エミュレータでは何も起こらない。
- **ウィンドウタイトルとカーソル形状** — 端末エミュレータのタイトルと、カーソルの形
  （ブロック・下線・縦棒と点滅の有無）を設定できる。終了時と一時停止時に元へ戻す。
- **端末デバイスと端末エミュレータの後始末** — raw モード・代替画面・マウストラッキング・フォーカス通知を
  終了時に必ず元へ戻す。
- **外部依存なし** — SwiftPM だけでビルドできる。

## 使い方

`Package.swift` に追加する。

```swift
dependencies: [
    .package(url: "https://github.com/MiyasakaKufu/tui-swift.git", branch: "main")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: [
        .product(name: "TUIKit", package: "tui")
    ])
]
```

最小限の TUIKit アプリは次のようになる。`@main` を付けた型がそのままエントリポイントになる。

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

`Application` の起動時に渡す `ApplicationOptions` は、`TerminalApp.options` で変える。

```swift
static var options: ApplicationOptions {
    ApplicationOptions(mouseTracking: .buttons, frameInterval: 1.0 / 30)
}
```

マウス（`ApplicationOptions.mouseTracking`）とフォーカス通知（`ApplicationOptions.reportsFocus`）は、
初期値では無効になっている。有効にした端末エミュレータだけが `.mouse` / `.focus` を送ってくるため、
使う TUIKit アプリが明示的に有効にする。`ApplicationOptions.mouseTracking` は `.buttons` で
押下・解放・ドラッグ・ホイールを、`.motion` でボタンを押していない間の移動（`.move`）も受け取る。
`.motion` はカーソルが動くたびにイベントが届くので、ホバーの強調やツールチップのように
移動そのものを使う TUIKit アプリだけが選ぶ。

kitty keyboard protocol（`ApplicationOptions.usesKeyboardProtocol`）は、初期値では有効になっている。
起動時に端末エミュレータへ対応状況を問い合わせ、対応していれば有効にする。対応していない
端末エミュレータでは、従来どおり時間切れでキーを確定させる。問い合わせを送りたくない TUIKit アプリ
だけ `false` にする。

ウィンドウタイトル（`ApplicationOptions.windowTitle`）とカーソル形状（`ApplicationOptions.cursorShape`）は、
どちらも初期値は `nil`、つまり端末エミュレータの設定のままにする。

```swift
static var options: ApplicationOptions {
    ApplicationOptions(windowTitle: "MyApp", cursorShape: .blinkingBar)
}
```

`Application.setWindowTitle(_:)` / `Application.setCursorShape(_:)` を呼び出せば、動作中にも
変えられる。どちらも終了時と一時停止時に元へ戻す。タイトルは `CSI 22 t` で
端末エミュレータに保存させ、`CSI 23 t` で戻させるため、この 2 つに対応しない端末エミュレータでは戻らない。

`Component.handle(_:)` にはデフォルトの実装（すべて `.ignored`）があるため、
表示だけの TUIKit アプリは `Component.body` だけで書ける。
raw モードでは Ctrl+C が SIGINT にならないので、`Component.handle(_:)` が
`.ignored` を返した Ctrl+C では、`ApplicationOptions.quitsOnControlC`（初期値は `true`）が
終了させる。自前で扱うなら `false` にする。
Ctrl+Z も同じくシグナルにならないため、`Component.handle(_:)` が `.ignored` を返した Ctrl+Z では、
`ApplicationOptions.suspendsOnControlZ`（初期値は `true`）が一時停止させる。
端末デバイスと端末エミュレータを元に戻してからプロセスを止め、再開したら raw モードと画面を
設定し直して `.resize` を通知する。`Application.suspend()` を呼び出せば、好きなキーで一時停止させることもできる。

外から SIGINT / SIGQUIT / SIGTERM / SIGHUP を受けたときは、イベントループを終えて端末デバイスと
端末エミュレータを元に戻す。`fatalError` や範囲外アクセスで落ちたときも、シグナルハンドラが
端末デバイスの raw モードと、端末エミュレータの代替画面・マウス受信・ブラケットペースト・
キーの形式・カーソル形状・ウィンドウタイトルを元に戻してから、シグナル本来の動作へ進む。

`Application` を直接組み立てることもできる。

```swift
try Application(root: Counter(), options: .default).run()
```

同梱のデモは次で起動する。

```
swift run tui-demo
```

## 曖昧幅（East Asian Ambiguous）

罫線素片（`─` `│` `╭`）、`…`、`█`、矢印などは East Asian Width が Ambiguous で、
端末エミュレータの設定によって `Cell` 1 個分にも 2 個分にも表示される。TUIKit は、初期値では
`Cell` 1 個分として扱う。

```swift
DisplayWidth.ambiguousWidth = .wide   // 全角として扱う
```

環境変数 `RUNEWIDTH_EASTASIAN` が `1` なら、最初の計算時に自動で
`.wide` になる（go-runewidth や tcell と同じ規則）。ロケールからの推測は端末エミュレータの設定と
食い違うとかえって崩れるため自動では行わないが、必要なら明示的に呼び出せる。

```swift
DisplayWidth.ambiguousWidth = DisplayWidth.resolveAmbiguousWidth(usingLocale: true)
```

1 回の計算だけ切り替えたい場合は `ambiguous:` を渡す。

```swift
DisplayWidth.width(of: "─", ambiguous: .wide)   // 2
```

`.wide` のときは枠線の罫線素片も `Cell` 2 個分になるため、枠線は ASCII 版（`+-|`）へ自動で切り替わる。

## 構成

| 層 | 主な型 | 役割 |
| --- | --- | --- |
| 端末 | `Terminal`, `SignalWatcher` | 端末デバイスの raw モード、端末エミュレータの代替画面、端末デバイスの大きさの取得、ウィンドウタイトルとカーソル形状、シグナル、異常終了時の復元 |
| 入力 | `InputParser`, `InputReader`, `KeyEvent`, `MouseEvent` | バイト列から `InputEvent` への増分解析 |
| 描画 | `Buffer`, `Cell`, `Renderer`, `Style` | `Cell` の二次元配列と、変わった `Cell` だけの書き出し |
| 文字 | `DisplayWidth`, `TextWrapping`, `TabExpansion` | 横方向の長さの計算、折り返し、タブの展開 |
| ビュー | `View`, `PrimitiveView`, `State`, `VStack`, `HStack`, `ZStack`, `Text`, `View` の拡張メソッド | レイアウトと `Buffer` への書き込み |
| 部品 | `ListView`, `TextField`, `ProgressBar`, `Binding` | `ListState`・`TextFieldState` を使って入力を受け付ける `View` と、`TerminalApp` に準拠する型のインスタンスプロパティを渡す `Binding` |
| 実行 | `TerminalApp`, `Application`, `Component` | エントリポイントとイベントループ |

### 画面を書き出す流れ

1. `Application` が `Component.body` の値を取得して `View` を組み立てる。
2. `View` を `Buffer`（`Cell` の二次元配列）へ書き込む。`View` は別の `View` のメソッドを直接呼び出さず、
   `RenderContext` のメソッドに `child` 引数として渡して、大きさを測り、`LayoutTraits` を取得し、
   書き込む。`View.body` を持つ `View` は、その `View.body` の `View` を測り、書き込む。
   `Application.draw()` をまたいで同じ `View` として扱われるかは、`RenderContext` のメソッドに渡された
   位置（`View.id(_:)` を付けた `View` はその引数）で決まる。
3. `Renderer` が、直前に書き出した `Buffer` と比べ、変わった `Cell` だけを端末デバイスへ書き出す。

`View` に準拠する型は値型で、`Application.draw()` のたびに作り直される。`Application.draw()` をまたいで
残す値は、次のように分けて置く。

| 使う場所 | 例 | 置き場所 |
| --- | --- | --- |
| 複数の `View` と `Component.handle(_:)` | `ListView` で選んでいる位置 | `TerminalApp` に準拠する型のインスタンスプロパティ。`Binding` で `ListView` などに渡す |
| 1 つの `View` の中だけ | `TextField` に入力した文字列 | `View` の `@State` を付けたプロパティ。`$` で得た `Binding` を `TextField` などに渡す |
| `ListView`・`TextField` の表示 | カーソル位置、スクロール位置、直前に書き込んだ矩形 | `TextFieldState` / `ListState`。`TerminalApp` に準拠する型が保持する |

```swift
private var name = ""
private let inputState = TextFieldState()

var body: some View {
    TextField(text: Binding(self, \.name), state: inputState)
}

func handle(_ event: InputEvent) -> EventResult {
    inputState.handle(event) ? .handled : .ignored   // 編集の結果が name に書き戻される
}
```

`Binding` は、別の場所にあるプロパティの値を取得するクロージャと書き換えるクロージャの組を持つ値型で、
`Binding(get:set:)` でも作れる。`ListView`・`TextField` が `Binding` で値を書き換えるのは
`ListState.handle(_:)`・`TextFieldState.handle(_: InputEvent)` の中だけで、
`View.render(into:rect:context:)` の中では書き換えない。

1 つの `View` の中だけで使う値は、`TerminalApp` に準拠する型のインスタンスプロパティにせず、
`@State` で持てる。

```swift
struct NameForm: View {
    let inputState: TextFieldState
    @State var name = ""

    var body: some View {
        VStack {
            TextField(text: $name, state: inputState)
            Text("\(name.count) 文字")
        }
    }
}
```

`@State` を付けたプロパティの値は `View` に準拠する型の値ではなく、TUIKit が `View` の位置ごとに持つ
記憶域に置かれ、`Application.draw()` をまたいで残る。ある `Application.draw()` の 1 回で `RenderContext` の
どのメソッドにも渡されなかった `View` の記憶域は、その `Application.draw()` の終わりに捨てる。
同じ位置に別の型の `View` が来たときも捨てる。

`Binding` を渡さない `TextField(state:)` / `ListView(items:state:)` も残している。
こちらは入力した文字列や選んでいる位置も `TextFieldState`・`ListState` が持ち、
`TextFieldState.text` や `ListState.selectedIndex` で値を取得する。

### レイアウトの規則

`View` は、`View.sizeThatFits(_:context:)` で自分の `Size` を返し、`View.layoutTraits(context:)` で
`LayoutTraits` を返す。`LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` は、余った `Size` を
どの割合で引き取るかを表す整数である。`VStack`・`HStack` は、並べる向きのもの（`HStack` では
`LayoutTraits.horizontalFlex`、`VStack` では `LayoutTraits.verticalFlex`）を使い、次の順で `Size` を配る。

1. その整数が 0 の `View` に、`View.sizeThatFits(_:context:)` の戻り値を割り当てる。
2. その整数が 1 以上の `View` には並べる向きに 0 を提案し、最小の `Size` だけ確保する。
3. 残りの `Size` を、その整数に比例して配る。
4. `Size` が足りない場合は後ろの `View` から削る。

`Spacer` と `Fill`、`.flexible()` を付けた `View` は、その整数が 1 以上になる。

## 対応する入力

| 区分 | 解釈するもの |
| --- | --- |
| 文字 | ASCII、UTF-8 マルチバイト（分割受信も可） |
| 制御 | Enter, Tab, Shift+Tab, Backspace, Delete, Insert, Escape |
| 移動 | ↑↓←→, Home, End, PageUp, PageDown |
| ファンクション | F1〜F12（SS3 形式・CSI `~` 形式の両方） |
| 修飾 | Ctrl, Alt, Shift（CSI の修飾パラメータを解釈） |
| マウス | 押下・解放・ドラッグ・ホイール 4 方向・拡張ボタン・移動（SGR 1006、移動は `.motion` のとき） |
| その他 | ブラケットペースト、フォーカス通知（`reportsFocus` で有効にしたとき） |
| kitty | CSI u 形式のキー（F13〜F35、テンキー、Ctrl+I と Tab の区別） |

## 動作環境

- Swift 6.0 以降
- macOS 15 以降、または Linux
- `hasPrefix(ANSI.csi)` か `hasPrefix(ANSI.osc)` が `true` の `String` を解釈する端末エミュレータ

## テスト

```
swift test
```

レイアウト、折り返し、表示幅、差分レンダリング、入力解析は
端末デバイスなしで検証できるようになっている。

## 開発

DocC・コメント・コミットログの書き方は `CONTRIBUTING.md` にまとめている。
書式のうち機械的に判定できるものは `swift test` で検査される。

## ライセンス

MIT License（`LICENSE` を参照）。
