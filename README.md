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
  全角文字がセルの境界で割れないように描画する。
- **宣言的なレイアウト** — `VStack` / `HStack` / `Spacer` / `border` などを組み合わせて画面を記述する。
- **入力の解析** — 矢印キー、ファンクションキー、修飾キー、マウス（SGR 1006）、
  ブラケットペーストを解釈する。分割して届いたシーケンスも正しく扱う。
- **端末の後始末** — raw モード・代替画面・マウストラッキングを終了時に必ず元へ戻す。
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

`handle(_:)` には既定実装（すべて `.ignored`）があるため、表示だけのアプリは `body` だけで書ける。
raw モードでは Ctrl+C が SIGINT にならないので、`Component` が処理しなかった Ctrl+C は
`ApplicationOptions.quitsOnControlC`（既定で有効）が終了させる。自前で扱うなら `false` にする。

`Application` を直接組み立てることもできる。

```swift
try Application(root: Counter(), options: .default).run()
```

同梱のデモは次で起動する。

```
swift run tui-demo
```

## 構成

| 層 | 主な型 | 役割 |
| --- | --- | --- |
| 端末 | `Terminal`, `SignalWatcher` | raw モード、代替画面、サイズ取得、SIGWINCH |
| 入力 | `InputParser`, `InputReader`, `KeyEvent`, `MouseEvent` | バイト列からイベントへの増分解析 |
| 描画 | `Buffer`, `Cell`, `Renderer`, `Style` | セル単位の画面バッファと差分出力 |
| 文字 | `DisplayWidth`, `TextWrapping` | 表示幅の計算と折り返し |
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
| マウス | 押下・解放・ドラッグ・ホイール（SGR 1006） |
| その他 | ブラケットペースト、フォーカス通知 |

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

## ライセンス

MIT License（`LICENSE` を参照）。
