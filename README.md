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

- **差分レンダリング** — 前フレームとの差分だけをエスケープシーケンスで送るため、
  ちらつかず、大きな画面でも出力量が小さい。
- **全角文字と絵文字に対応** — East Asian Width と結合文字を考慮して桁数を計算し、
  全角文字がセルの境界で割れないように描画する。曖昧幅の文字は 1 桁と 2 桁から選べる。
  `TextField` は国旗や ZWJ で結合した絵文字を書記素クラスタ単位で 1 文字として扱う。
- **タブの展開** — タブは幅を計算する前に次のタブストップまでの空白へ展開する。
  既定のタブ幅は 4 桁で、`Text(_:tabSize:)` や `.tabStops(every:)` で変えられる。
- **宣言的なレイアウト** — `VStack` / `HStack` / `Spacer` / `border` などを組み合わせて画面を記述する。
- **入力の解析** — 矢印キー、ファンクションキー、修飾キー、マウス（SGR 1006）、
  ブラケットペーストを解釈する。分割して届いたシーケンスも正しく扱う。
  端末が対応していれば kitty keyboard protocol を使い、Ctrl+I と Tab のように
  従来は同じバイト列だったキーを区別する。
- **IME への対応** — 入力欄は描画のたびに `TextFieldState.renderedCursorPoint` へ
  端末カーソルを置くべき位置を記録する。`Component.cursorPosition` でそれを返すと、
  変換中の文字と変換候補が入力欄の位置に出る。
- **ウィンドウタイトルとカーソル形状** — 端末のタイトルと、カーソルの形
  （ブロック・下線・縦棒と点滅の有無）を設定できる。終了時と一時停止時に元へ戻す。
- **端末の後始末** — raw モード・代替画面・マウストラッキング・フォーカス通知を
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

最小限のアプリケーションは次のようになる。`@main` を付けた型がそのままエントリポイントになる。

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

起動時の設定は `options` で変える。

```swift
static var options: ApplicationOptions {
    ApplicationOptions(tracksMouse: true, frameInterval: 1.0 / 30)
}
```

マウス（`tracksMouse`）とフォーカス通知（`reportsFocus`）は既定で無効になっている。
有効にした端末だけが `.mouse` / `.focus` を送ってくるため、使うアプリが明示的に有効にする。

kitty keyboard protocol（`usesKeyboardProtocol`）は既定で有効になっている。起動時に端末へ
対応状況を問い合わせ、対応していれば有効にする。対応していない端末では、従来どおり
時間切れでキーを確定させる。問い合わせを送りたくないアプリだけ `false` にする。

ウィンドウタイトル（`windowTitle`）とカーソル形状（`cursorShape`）は、どちらも既定で
`nil`、つまり端末の設定のままにする。

```swift
static var options: ApplicationOptions {
    ApplicationOptions(windowTitle: "MyApp", cursorShape: .blinkingBar)
}
```

`Application.setWindowTitle(_:)` / `Application.setCursorShape(_:)` を呼べば、動作中にも
変えられる。どちらも終了時と一時停止時に元へ戻す。タイトルは `CSI 22 t` で端末のスタックへ
積んでおき、`CSI 23 t` で戻すため、タイトルのスタックに対応しない端末では戻らない。

`handle(_:)` には既定実装（すべて `.ignored`）があるため、表示だけのアプリは `body` だけで書ける。
raw モードでは Ctrl+C が SIGINT にならないので、`Component` が処理しなかった Ctrl+C は
`ApplicationOptions.quitsOnControlC`（既定で有効）が終了させる。自前で扱うなら `false` にする。
Ctrl+Z も同じくシグナルにならないため、処理しなかった Ctrl+Z は
`ApplicationOptions.suspendsOnControlZ`（既定で有効）が一時停止させる。端末を元に戻してから
プロセスを止め、再開したら raw モードと画面を設定し直して `.resize` を通知する。
`Application.suspend()` を呼べば、好きなキーで一時停止させることもできる。

外から SIGINT / SIGQUIT / SIGTERM / SIGHUP を受けたときはイベントループを終えて端末を戻す。
`fatalError` や範囲外アクセスで落ちたときも、シグナルハンドラが raw モード・代替画面・
マウス受信・ブラケットペースト・キーの形式・カーソル形状・ウィンドウタイトルを元に戻してから、
本来のクラッシュ処理へ進む。

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
端末の設定によって 1 桁にも 2 桁にも表示される。TUIKit は既定で 1 桁として扱う。

```swift
DisplayWidth.ambiguousWidth = .wide   // 全角として扱う
```

環境変数 `RUNEWIDTH_EASTASIAN` が `1` なら、最初の計算時に自動で `.wide` になる
（go-runewidth や tcell と同じ規則）。ロケールからの推測は端末側の設定と食い違うと
かえって崩れるため自動では行わないが、必要なら明示的に呼べる。

```swift
DisplayWidth.ambiguousWidth = DisplayWidth.resolveAmbiguousWidth(usingLocale: true)
```

1 回の計算だけ切り替えたい場合は `ambiguous:` を渡す。

```swift
DisplayWidth.width(of: "─", ambiguous: .wide)   // 2
```

`.wide` のときは枠線の罫線素片も 2 桁になるため、枠線は ASCII 版（`+-|`）へ自動で切り替わる。

## 構成

| 層 | 主な型 | 役割 |
| --- | --- | --- |
| 端末 | `Terminal`, `SignalWatcher` | raw モード、代替画面、サイズ取得、タイトルとカーソル形状、シグナル、クラッシュ時の復元 |
| 入力 | `InputParser`, `InputReader`, `KeyEvent`, `MouseEvent` | バイト列からイベントへの増分解析 |
| 描画 | `Buffer`, `Cell`, `Renderer`, `Style` | セル単位の画面バッファと差分出力 |
| 文字 | `DisplayWidth`, `TextWrapping`, `TabExpansion` | 表示幅の計算、折り返し、タブの展開 |
| ビュー | `View`, `VStack`, `HStack`, `Text`, 各種修飾子 | レイアウトと描画 |
| 部品 | `ListView`, `TextField`, `ProgressBar` | 状態を持つウィジェット |
| 実行 | `TerminalApp`, `Application`, `Component` | エントリポイントとイベントループ |

### 描画の流れ

1. `Application` が `Component.body` を読んで `View` のツリーを組み立てる。
2. ツリーを `Buffer`（`Cell` の二次元配列）へ描画する。
3. `Renderer` が前フレームの `Buffer` と比較し、変わったセルだけを書き出す。

ビューは値型で状態を持たない。選択位置や入力内容のような状態は
`ListState` / `TextFieldState` のようなクラスに置き、`Component` が保持する。

### レイアウトの規則

各ビューは `sizeThatFits(_:)` で希望サイズを返し、`layoutTraits` で
「余った領域を引き取る重み」を表す。スタックは次の順で領域を配る。

1. 重み 0 のビューに希望サイズを割り当てる。
2. 重み 1 以上のビューには主軸 0 を提案し、最小サイズだけ確保する。
3. 残りを重みに比例して配る。
4. 領域が足りない場合は後ろのビューから削る。

`Spacer` と `Fill`、`.flexible()` を付けたビューが重みを持つ。

## 対応する入力

| 種類 | 内容 |
| --- | --- |
| 文字 | ASCII、UTF-8 マルチバイト（分割受信も可） |
| 制御 | Enter, Tab, Shift+Tab, Backspace, Delete, Insert, Escape |
| 移動 | ↑↓←→, Home, End, PageUp, PageDown |
| ファンクション | F1〜F12（SS3 形式・CSI `~` 形式の両方） |
| 修飾 | Ctrl, Alt, Shift（CSI の修飾パラメータを解釈） |
| マウス | 押下・解放・ドラッグ・ホイール 4 方向・拡張ボタン（SGR 1006） |
| その他 | ブラケットペースト、フォーカス通知（`reportsFocus` で有効にしたとき） |
| kitty | CSI u 形式のキー（F13〜F35、テンキー、Ctrl+I と Tab の区別） |

## 動作環境

- Swift 5.9 以降
- macOS 13 以降、または Linux
- ANSI エスケープシーケンスを解釈する端末

## テスト

```
swift test
```

レイアウト、折り返し、表示幅、差分レンダリング、入力解析は
端末なしで検証できるようになっている。

## 開発

DocC・コメント・コミットログの書き方は `CONTRIBUTING.md` にまとめている。
書式のうち機械的に判定できるものは `swift test` で検査される。

## ライセンス

MIT License（`LICENSE` を参照）。
