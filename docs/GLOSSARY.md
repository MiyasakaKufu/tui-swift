# 用語集

このリポジトリの issue・コード・DocC・`//` コメント・コミットログ・PR で、下の表の「指すもの」を書くときは、「書き方」のとおりに書く。

## 書き方の規則

1. 1 つのものに 1 つの書き方を使い、同じ書き方を別のものに使わない。
2. 使っている意味のほかに、外部（国語辞典・JIS・Swift と SwiftUI の文書）で定着した別の意味を持つ語を、用語に使わない。語義の 1 つが使っている意味と一致していても使わない。例外は規則 7 の語だけ。
3. 「状態」「値」「内容」「処理」「設定」「結果」「種類」「部分」「仕組み」「機構」「機能」などの抽象語を、指すものを書かずに使わない。指すものにコードの名前があれば、その名前をバッククォートで囲んで書く。
4. 「〜者」「〜側」のように相手のある語は、相手を書く（「TUIKit を使う開発者」「TUIKit アプリを端末エミュレータで操作する人」）。
5. 比喩を用語に使わない。木構造にたとえた語（親、子、ルート、木、ツリー）も使わない。`View` どうしの関係は、`RenderContext` のメソッドに `child` 引数として渡す `View` と、`context` 引数で `RenderContext` を受け取る `View` で書く。「呼び出し元」「呼び出し先」は使わない。
6. `Sources/TUIKit/` ディレクトリの Swift の宣言は、型名・名前・引数ラベルまで書く。多重定義があれば引数の型も書く（`View.padding(_: EdgeInsets)`）。プロトコルの要件と、同じプロトコルの extension にあるデフォルトの実装の組（`View.sizeThatFits(_:context:)` など）は、名前が要件を指す。
7. 次の Swift の語は、The Swift Programming Language が定義する意味でだけ使う。宣言（declaration）、型（type）、メソッド（method）、プロパティ（property）、インスタンスプロパティ（instance property）、イニシャライザ（initializer）、関連型（associated type）、デフォルトの実装（default implementation）、返す（return。Return Statement の節が述べる、式の値を呼び出し元へ出す意味。制御が呼び出し元へ戻る意味には使わない）。訳語は Apple Developer の日本語版に合わせた。「ケース」「既定」「実装」（単独）は使わない。
8. 次の語は、POSIX（The Open Group Base Specifications）が定義する意味でだけ使う。端末デバイス（terminal device）。訳語は Apple Developer の日本語版に合わせた。
9. 「端末」を単独で使わない。指すものに応じて「端末デバイス」か「端末エミュレータ」で書き、両方を指すときは 2 つを並べて書く。
10. 関数・メソッドなど実行されるコードを動かすことは「呼び出す」「呼び出し」で書き、「呼ぶ」「呼ばれる」は使わない。目的語には、動かすコード（メソッドなど）を書く。
11. 次の書き方は、規則 2 に合わないが、ほかに書き方がないため例外として使う。
    - 「プロセス」: 「手順」「過程」の意味も持つが、使う文の中ではその意味で通らない。
    - 「TUIKit を使う開発者」: 「開発」「デベロッパ」の別の意味が残るが、コードの名前でも書けない。
12. 規則 2 と規則 5 は、表の「指すもの」と「補足」に書く語にも当てる。ただし、辞書に別の語義があるかではなく、使う文の中でほかの語義に読まれないかで判定する。使い方にあたる語義が辞書にない語（「読む」など）は使わない。
13. 読み違いを防ぐために語を足したときは、足した語ごとに、(0) 足さなくても読み違いが起きるか、(1) 足した語が書きたいことから外れていないか、(2) 足した語が別の読みを加えていないかを、その語を使う文の中で確かめる。

## プログラムと `Application`

| 指すもの | 書き方 | 補足 |
|---|---|---|
| TUIKit を使う開発者が `@main` を付けて書く型 | `TerminalApp` に準拠する型 | `TerminalApp` は `Component` を継承している。`Component` は #105 で廃止する予定 |
| 端末デバイスを raw モードにし、`InputReader` が端末デバイスから受け取ったバイト列を `InputEvent` にすることと `Buffer` を端末デバイスへ書き出すことを繰り返し、終了時に端末デバイスの termios と、端末エミュレータへ送ったモードを元に戻す型 | `Application` | |
| 端末デバイスへの書き出しと termios の書き換え、端末エミュレータへ送るモードの切り替えを行う型 | `Terminal` | |
| `Terminal.inputDescriptor`・`Terminal.outputDescriptor` がつながり、`isatty` が真になる文字デバイス（POSIX の terminal device） | 端末デバイス | |
| DEC VT102 などの機器を模倣し、端末デバイスへ書き出されたバイト列を解釈して表示するプログラム（xterm など）。端末デバイスが POSIX の pseudo-terminal の subsidiary device のときは、対になる manager device を操作する | 端末エミュレータ | |
| 動いているプログラム全体 | プロセス | |
| TUIKit を使って作ったプログラム（`Sources/TUIDemo` のデモを含む） | TUIKit アプリ | 「アプリ」を単独で使わない |
| TUIKit を使ってプログラムを書く人 | TUIKit を使う開発者 | |
| TUIKit アプリを端末エミュレータで操作する人 | TUIKit アプリを端末エミュレータで操作する人 | |
| `Application` の起動時に渡す、`ApplicationOptions.mouseTracking`・`ApplicationOptions.frameInterval` などのプロパティを持つ型 | `ApplicationOptions` | 個々のプロパティは名前で書く |
| `Application.draw()` の 1 回の呼び出し | `Application.draw()` の 1 回 | `ApplicationOptions.frameInterval` は、この呼び出しの間隔 |

## `View`

| 指すもの | 書き方 | 補足 |
|---|---|---|
| `Text`・`VStack` などが準拠するプロトコル | `View` | |
| `View.body` で別の `View` を返す `View` | `View.body` を持つ `View` | |
| `View.body` を持たず、`View.sizeThatFits(_:context:)` と `View.render(into:rect:context:)` を自分で書く `View` | `PrimitiveView` | `View.layoutTraits(context:)` にはデフォルトの実装がある |
| `proposal` 引数に渡された `Size` の範囲で、自分の `Size` を返すメソッド | `View.sizeThatFits(_:context:)` | 戻り値は「`View.sizeThatFits(_:context:)` の戻り値」と書く |
| 自分の `LayoutTraits` を返すメソッド | `View.layoutTraits(context:)` | |
| `Buffer` の `Cell` に文字と `Style` を書き込むメソッド | `View.render(into:rect:context:)` | |
| 別の `View` の `View.sizeThatFits(_:context:)`・`View.layoutTraits(context:)`・`View.render(into:rect:context:)` を呼び出すために、`View` が `context` 引数で受け取る型 | `RenderContext` | `View` は、この引数の `RenderContext.sizeThatFits(of:index:proposal:)`・`RenderContext.layoutTraits(of:index:)`・`RenderContext.render(_:index:into:rect:)` に別の `View` を `child` 引数として渡して呼び出す |
| `Application` が最初にメソッドを呼び出す `View` から、`RenderContext` のメソッドに `child` 引数として渡された `View` を順にたどったときの、`ViewPath.Component` の並び | `ViewPath` | internal |
| `RenderContext` のメソッドに渡された `index:` 引数（`.index(_:)`）か、`View.id(_:)` の引数（`.key(_:)`） | `ViewPath.Component` | internal。プロトコル `Component` とは別物 |
| `ViewPath` と型が同じ `View` に、`Application.draw()` をまたいで使われ続けるクラス | `ViewNode` | internal。`ViewNode.id` が同じなら、同じ `View` として扱われる |
| `View.id(_:)` に渡した引数。`ViewPath.Component` の `.key(_:)` になる | `View.id(_:)` の引数 | |
| `View` に準拠する型の格納プロパティに `@State` として付け、そのプロパティを `Application.draw()` をまたいで残す型 | `State` | プロパティは `ViewNode` が持つ。`$` で得る `Binding` は `State.projectedValue` |
| `View` の拡張として定義された `View.padding(_: EdgeInsets)`・`View.border(_:style:title:titleStyle:)` などのメソッド | `View` の拡張メソッド | 個々のメソッドは名前で書く |
| `ListView`・`TextField`・`ProgressBar` | `ListView`・`TextField`・`ProgressBar` | まとめて書くときは「`Sources/TUIKit/Widgets/` ディレクトリの型」 |
| `TextFieldState.cursor`・`ListState.scrollOffset` などを持つクラス | `ListState`・`TextFieldState` | 2 つをまとめる語は置かない。5cf1d9a は、`View` の `State` へ移せるのは #53 の後と書いている |
| 別の場所にあるプロパティの値を取得し、書き換える型 | `Binding` | |
| `TextField` の `text:` 引数と `ListView` の `selection:` 引数に、`Binding` で渡すプロパティ。`TerminalApp` に準拠する型のインスタンスプロパティか、`View` の `@State` を付けたプロパティ | `Binding` で渡すプロパティ | |
| `TextFieldState`・`ListState` が持つ、`Binding` で渡さないプロパティ | `TextFieldState.cursor`・`ListState.scrollOffset`・`ListState.renderedRect` など、それぞれの名前 | |

## レイアウト

| 指すもの | 書き方 | 補足 |
|---|---|---|
| `VStack`・`HStack` が中の `View` に `Size` を配ったあとに残る `Size` を、どの割合で引き取るかを表す整数 | `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` | `axis` に合う方の 1 つだけを指すときは `LayoutTraits.flex(on:)` の値で書く |
| `PaddingView.content` の上下左右に空ける長さ（`Cell` の数で表す） | `EdgeInsets`（`View.padding(_: EdgeInsets)` の引数） | |
| `VStack`・`HStack` が中の `View` に `Size` を配ったあとに残る `Size` | `VStack`・`HStack` が配ったあとに残る `Size` | |
| `RenderContext.sizeThatFits(of:index:proposal:)` の `proposal` 引数に渡し、`child` 引数の `View` の `View.sizeThatFits(_:context:)` へ届く `Size` | `View.sizeThatFits(_:context:)` の `proposal` 引数 | |

## ディレクトリ

| 指すもの | 書き方 | 補足 |
|---|---|---|
| `Sources/TUIKit/` の下の `App/`・`Input/`・`Render/` などのディレクトリ | `Sources/TUIKit/` の下のディレクトリ名（`App/` など） | パスは末尾の `/` まで書き、「ディレクトリ」と添える |

## `Cell` と `Buffer`

| 指すもの | 書き方 | 補足 |
|---|---|---|
| 端末エミュレータが表示する 1 文字分のます目 | `Cell` | |
| 横方向の長さ | `Cell` の数 | `Size.width`。縦は `Buffer` の行の数（`Size.height`） |
| 横方向の位置 | `Point.x` | 左端が 0 |
| 文字列が端末エミュレータで占める横方向の長さ（`Cell` の数で表す） | `DisplayWidth.width(of: String, ambiguous: AmbiguousWidth)` の戻り値 | |
| East Asian Width が Ambiguous の文字を `Cell` 何個分として扱うか | `DisplayWidth.AmbiguousWidth` | |
| 端末エミュレータが表示する全体を表す `Cell` の二次元配列 | `Buffer` | |
| 直前に書き出した `Buffer` と比べ、変わった `Cell` だけを端末デバイスへ書き出す型 | `Renderer` | |
| 端末デバイスへ書き出す `String` のうち、`hasPrefix(ANSI.escape)` が `true` のもの | `hasPrefix(ANSI.csi)` か `hasPrefix(ANSI.osc)` が `true` の `String` | 定数と関数は `ANSI` にある。`Style` の SGR も `ANSI.csi` から作る |

## `InputEvent` と `Component.Message`

| 指すもの | 書き方 | 補足 |
|---|---|---|
| `InputReader` が端末デバイスから受け取ったバイト列を `InputParser` が解釈したもの（`.key`・`.mouse` など）か、`Application` が端末デバイスの大きさの変化から作るもの（`.resize`）を表す型 | `InputEvent` | |
| 別スレッドや `Task` から `MessageSender.send(_:)` で `Application` へ送る引数の型 | `Component.Message` | |
| `Component.Message` を `Application` へ送る型 | `MessageSender` | |
| `TerminalApp` に準拠する型が `Component.Message` を受け取るメソッド | `Component.receive(_:)` | |
| `TerminalApp` に準拠する型が `InputEvent` を受け取るメソッド | `Component.handle(_:)` | `ListState.handle(_:)`・`TextFieldState.handle(_: InputEvent)` は別の宣言 |

## #98 の表の行

| 指すもの | 書き方 | 補足 |
|---|---|---|
| #98 の決定 3 で、`TerminalApp` に準拠する型から一度だけ呼び出すとしたメソッド | `Application.copyToClipboard(_:limit:)`・`Application.suspend()` | 2 つをまとめる語は置かない |
| `TerminalApp` に準拠する型のインスタンスプロパティで、`Application` が `Application.draw()` のたびにプロパティの値を取得するもの | 名前で書く（`Component.cursorPosition` など） | |
| `Application` が保持するプロパティとその型で、すべての `View` がプロパティの値を取得するもの | 名前で書く（`ApplicationOptions.ambiguousWidth` など） | まとめる語は置かない。まだコードに無いもの（#53、#73）は issue 番号で書く |

## SwiftUI と同じ名前で、振る舞いが違うもの

この表の名前の振る舞いは、SwiftUI の同じ名前のものと違う。

| 名前 | TUIKit での振る舞い |
|---|---|
| `VStack` / `HStack` | 引数の順は `spacing:` → `alignment:`。`alignment:` を省くと `.leading` / `.top`。`spacing:` は `Int` で、省くと 0 |
| `Spacer` | 入っている `VStack`・`HStack` に関係なく、縦横両方に伸びる。`minLength:` を省くと 0 |
| `Divider` | 向きは入っている `VStack`・`HStack` に合わせず、`axis:` で決める（省くと `.horizontal`） |
| `View.padding(horizontal:vertical:)` | 引数を省いた `padding()` はこのメソッドを呼び出し、空ける幅は 0 |
| `View.border(_:style:title:titleStyle:)` | 枠線を `BorderView.content` の外側に足す。`BorderView` は `BorderView.content` より縦横に 2 ずつ大きい |
| `View.frame(width:height:horizontalAlignment:verticalAlignment:)` | `horizontalAlignment:`・`verticalAlignment:` を省くと `.leading`・`.top`。揃えで動くのは `FrameView` の矩形で、`FrameView.content` はその矩形いっぱいに書き込まれる |
| `Text` | `wrap:` を省くと `.truncate` で、折り返さずに末尾を省略する |
| `Binding` | プロパティラッパーではない。`$` と `projectedValue` は無い（`$` で `Binding` を返すのは `State.projectedValue`） |
| `ViewBuilder` | `[any View]` を返す |
