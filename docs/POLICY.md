# 方針

TUIKit のこれからの変更が従う方針と、まだ決まっていない設計の論点をまとめる。この文書は規範で、反する変更は差し戻す。変え方は `CONTRIBUTING.md` の「方針」にある。

## 書き方

- 載せるのは、知らずにコードを書くと差し戻しになる方針だけ。コードを読めば分かることは載せない。
- 今有効な方針だけを載せる。覆された方針は消す。経緯は git log と PR に残る。
- 決まった方針は、1 つごとに見出しを立て、「決定」「理由」「捨てた案」を書く。理由と捨てた案は、issue を読まなくても分かるように、この文書の中に書く。issue 番号は「経緯」として最後に添えるだけにする。
- まだ決まっていない論点は、1 つごとに見出しを問いの形で立て、「当たる変更」と、分かっていれば「選択肢」を書く。「当たる変更」は、コーディングエージェントが差分と照らして当たるかを判定できる具体さで書く。
- 論点が決まったら、「まだ決まっていない論点」から消し、「決まった方針」へ書く。
- 1 項目だけを読んでも分かるように書く。ほかの項目を前提にしない。宣言の名前は `docs/GLOSSARY.md` の書き方に従う。

## 目指すもの

- TUIKit を使う開発者が、TUIKit アプリを組み立てるための公開ライブラリ。
- SwiftUI と同じ書き方をすれば、SwiftUI と同じ振る舞いになる。TUIKit の型は SwiftUI の名前を採っているので、同じ書き方で違う振る舞いになると、警告も無いまま TUIKit アプリが壊れる。
- `@State` を持てる `View` を組み合わせて画面を作る。値をすべて TUIKit アプリが持ち、描画のたびに渡す形（Ratatui の形）は取らない。

## やらないこと

- Windows（ConPTY）への対応。動作を保証できる環境が手元に無い。
- 端末エミュレータで成り立たない SwiftUI の API。`preferredColorScheme(_:)`、`ShapeStyle`、`.tertiary`・`.quaternary`、`Color.accentColor`、`KeyPress` の phases（押し続ける・離す。端末デバイスへ届くバイト列で区別できない）。
- GUI の枠組みと同じプロセスで部品として使うこと。TUIKit はシグナル、端末デバイスの termios、`@main` を押さえる。
- コマンドライン引数の解析と、起動するかどうかの判断。TUIKit を使う開発者が書く。

## 決まった方針

### `View` は `View.body` で組み立て、別の `View` は `RenderContext` を通して測り、描く

- 決定: 画面は `View.body` を持つ `View` と `PrimitiveView` で組み立てる。別の `View` の `View.sizeThatFits(_:context:)`・`View.layoutTraits(context:)`・`View.render(into:rect:context:)` は直接呼び出さず、`RenderContext.sizeThatFits(of:slot:proposal:)`・`RenderContext.layoutTraits(of:slot:)`・`RenderContext.render(_:slot:into:rect:)` に `child` 引数として渡して呼び出す。
- 理由: 直接呼び出すと TUIKit が `ViewPath` を数えられず、その `View` の `@State` とフォーカスが結び付かない。`View.body` で組み立てた `View` は、TUIKit が `ViewNode` として扱える。
- 捨てた案:
  - `View.body` を持たせず、`RenderContext` を通すことだけを入れる案。`@State` を持つ `View` の中身を TUIKit を使う開発者が手で書くことになり、後から `View.body` を入れると公開 API が変わる。
  - 値をすべて TUIKit アプリが持ち、描画のたびに渡す案（Ratatui の形）。`@State` を入れられない。
  - `View.layoutTraits(context:)` だけは `RenderContext` を通さない案。`@State` で `LayoutTraits` が変わる `View` で、`VStack`・`HStack` が配ったあとに残る `Size` の配分だけが初期値のままになる。
- 経緯: #97, #101, #102

### `View` の同一性は、`slot` 引数と書いた位置で決める

- 決定: `ViewNode` は `ViewPath` で決まる。`ViewPath.Component` は、`slot` 引数と、書いた位置（`View.id(_:)` の引数があればその引数）の組。`if`-`else` の 2 つの分岐に書いた `View` は、型が同じでも別の `View` として扱う。同じ `ViewPath` で型が変わったら `ViewNode` を作り直す。`View` の並びは `ViewList` で渡し、`ViewList.Element` を作れるのは TUIKit の中だけにする。
- 理由: 書いた位置を通し番号にすると、前に置いた `if` の中の `View` が現れたり消えたりしたとき、後ろの `View` の `@State`・フォーカス・`View.task(_:)` の `Task` が初めからになる。分岐を区別しないと、`else` 側の `View` が `if` 側の別の `View` の `@State` を引き継ぐ。型が変わっても `ViewNode` を残すと、別の `View` が前の `View` の `@State` を引き継ぐ。
- 捨てた案:
  - `ViewBuilder` が各 `View` を内部の型で包む案。`ViewBuilder` のクロージャを 2 つ受け取る `View` で、別々の要素が同じ `ViewPath` になる。
  - SwiftUI のように `if` を 1 つの `View` にし、`VStack` などがほどく案。`ViewBuilder` のクロージャを受け取るすべての `View` に、ほどくコードが要る。
  - `RenderContext` のメソッドを呼び出した順に数える案。測るときと描くときで、同じ `View` に別の番号が付く。
- 経緯: #102, #143

### `PrimitiveView.visitChildren(_:)` にデフォルトの実装を置かない

- 決定: `RenderContext` のメソッドに `child` 引数として渡しうる `View` を持つ `PrimitiveView` は、`PrimitiveView.visitChildren(_:)` を書く。`PrimitiveView.visitChildren(_:)` にデフォルトの実装を置かない。描画より前にたどったが、測りも描きもしなかった `View` の `ViewNode` も残す。
- 理由: デフォルトの実装があると、書き忘れた `PrimitiveView` が持つ `View` が、たどった `View` の一覧から黙って漏れ、フォーカスとホバーの対象にならない。たどった `View` の `ViewNode` を捨てると、ウィンドウを縮めただけで `@State` が失われる。
- 捨てた案:
  - 要件を `View` に置く案。`View.body` を持つ `View` 向けのデフォルトの実装が `PrimitiveView` にも選ばれ、書き忘れると `View.body` の取得でプロセスが止まる。
  - `Application.draw()` の回数で数えた猶予の後に `ViewNode` を捨てる案。`Application.draw()` は入力のたびに行うので間隔が一定せず、回数が時間の意味を持たない。
- 経緯: #144

### `TerminalApp` に準拠する型は構造体にし、値は `@State` で持つ

- 決定: `TerminalApp` は `AnyObject` を要求しない。クラスで準拠すると、`Application` のイニシャライザが `precondition` で止める。値は `@State` を付けたプロパティに置く。`State` を `ViewNode` に結び付けるには `Mirror` を使い、マクロは使わない。結び付ける前の `State` は、読めば初期値を返し、代入は捨てる。
- 理由: `TerminalApp` に `Observable` を求めると、TUIKit を使う開発者にモデルの型を宣言させることになる。求めずに任意にすると、付け忘れたときに黙って再描画されない。構造体と `@State` にすれば、SwiftUI の `App` と同じ形になる。マクロを使うと、swift-syntax のビルドが TUIKit を使う開発者に乗る。
- 捨てた案:
  - `TerminalApp` に `Observable` を求める案、任意にする案。上の理由。
  - 結び付ける前の `State` を読んだら `precondition` で止める案。`View.body` の外で `View` を作って読むのは正当な使い方。
- 経緯: #100, #167

### `TextField`・`ListView` の値は `Binding` で受け取り、描画の中では書き戻さない

- 決定: `TextField` の文字列は `text:` 引数、`ListView` の選択位置は `selection:` 引数に `Binding` で受け取る。`TextFieldState.cursor`・`ListState.scrollOffset` など `Binding` で渡さないプロパティは、`TextFieldState`・`ListState` が持つ。`Binding` は `TextField`・`ListView` のイニシャライザで `TextFieldState`・`ListState` に渡す。書き戻すのは `TextFieldState.handle(_: InputEvent)`・`ListState.handle(_:)` などの入力を受け取るメソッドの中だけで、`View.render(into:rect:context:)` の中では書き戻さない。
- 理由: 入力を受け取るたびに `Binding` を渡すと、`View.body` と `TerminalApp.handle(_:)` で別々に組み立てることになり、食い違ったときに描いた値と編集する値が別物になる。`Application.draw()` の 1 回の中で同じ `View` を測るときと描くときの 2 回たどるので、描画の中に副作用を置けない。
- 捨てた案: `state.handle(event, text: binding)` のように、入力を受け取るたびに `Binding` を渡す案。上の理由。
- 経緯: #99

### 再描画は状態の変化だけで起こす

- 決定: 再描画は、`Application.draw()` の 1 回で読んだ状態が変わったときだけ起こす（`withObservationTracking`）。一定の間隔で `Application` を起こすものや、値を送って `Application` を起こす口を置かない。時間とともに変わる表示は、`View.task(_:)` の中で `Task.sleep` を挟みながら `@State` を付けたプロパティへ代入して書く。再描画の回数の上限は `ApplicationOptions.maximumFrameRate` で決める。参照型に値を置くなら `@Observable` を付ける。
- 理由: 何も変わらなければ何もしない。SwiftUI と同じ振る舞いで、TUIKit の名前から期待される振る舞いに揃う。上限が無いと、テストで 0.5 秒に 2743 回描いた。
- 捨てた案:
  - 一定の間隔で再描画する案。変化が無くても `View.body` をすべて評価する。
  - 一定の間隔で値を比べる案。値の型が自由なので比べられない。
  - `ApplicationOptions.frameInterval` と `TerminalApp.update(elapsed:)` を残す案。回数の上限とどちらを優先するかを決めることになる。
  - `MessageSender` と `TerminalApp.receive(_:)` で値を送る案。SwiftUI に対応するものが無い。
- 経緯: #54, #167

### `View` と `Application` などを `@MainActor` に隔離する

- 決定: `View`・`PrimitiveView`・`TerminalApp`・`Application`・`ListState`・`TextFieldState` を `@MainActor` に隔離する。`Application.run()` は async にする。端末デバイスから読むときは、専用のスレッドで `poll(2)` で待つ。
- 理由: 別の実行文脈から `View` や `ListState` に触るコードが error になり、`@unchecked Sendable` を宣言しても消えない。隔離しなければ診断は warning で、数行の宣言で消える。`@MainActor` を選んだのは、TUIKit がシグナル・termios・`@main` を押さえていて主アクタを占有して困る相手がいないことと、`@main` が `@MainActor` を特別に扱うため。
- 捨てた案:
  - 同期のループとロック付きのキューで渡す案。上の理由。
  - 専用のグローバルアクタにする案。`main()` を `nonisolated` にしてアクタへ入り直す一段が要る。
  - `LoopEventQueue` を actor にする案。同期の文脈から入れると `Task` を介することになり、入れた順が崩れる。`Mutex` で守る。
  - `Terminal` の `deinit` で端末デバイスの termios を戻す案。`deinit` は隔離できない。`CrashRestorer` がプロセスの終了時に戻す。
- 経緯: #106

### 並行性検査の指摘を宣言で黙らせない

- 決定: `Sources` で `@unchecked Sendable` と `nonisolated(unsafe)` を使わない。シグナルハンドラが読み書きする値は CTUIShim の C に置き、`CrashRestorer` のシグナルハンドラは C で書く。
- 理由: 宣言で黙らせると、`@MainActor` への隔離で越境を error にした狙いが TUIKit 自身の中で成り立たなくなる。シグナルハンドラの中で触ってよいのは `volatile sig_atomic_t` などに限られる。Swift のコードは参照カウントの操作やメモリの確保が入りうるので、非同期シグナル安全を保証できない。
- 捨てた案:
  - `@MainActor` や `Mutex` でシグナルハンドラが読む値を守る案。シグナルハンドラの中ではロックを取れない。
  - 値だけを C に置き、`CrashRestorer` のシグナルハンドラを Swift で書く案。上の理由。
- 経緯: #109

### TUIKit アプリ全体に効くものは `Application` が持ち、`RenderContext` に命令を載せない

- 決定: フォーカスやホバーなど TUIKit アプリ全体に効くものは、`Application` が持つ internal の `ApplicationContext` に置き、TUIKit を使う開発者に保持させない。`RenderContext` が公開するのは、`RenderContext.screen`・`RenderContext.ambiguousWidth` と、別の `View` を測り、描くメソッドだけで、命令を載せない。`TerminalApp` に準拠する型が値を決めるものは、命令ではなく宣言にする（`TerminalApp.isFinished`・`TerminalApp.cursorPosition`）。`@TaskLocal` などの暗黙のグローバルを使わない。
- 理由: `Application` は generic なので、参照を出すと `Application<DemoApp>` のような型が公開 API に出る。命令にすると、TUIKit アプリが持つ値と端末エミュレータに反映された値が二重になり、ずれうる。`Application.draw()` の 1 回の中で同じ `View` を 2 回たどるので、描画の側に副作用を置けない。暗黙のグローバルは `View.render(into:rect:context:)` の中からも読める。
- 捨てた案:
  - フォーカスを管理する型を公開し、TUIKit を使う開発者に保持させる案。TUIKit の中の都合を公開プロトコルの要件として外へ出すことになる。
  - `@TaskLocal` で渡す案。上の理由。
  - `TerminalApp.isFinished` と別に終了の命令を残す案。同じ値が 2 か所にある。
- 経緯: #98, #105。今も public の命令として残っている `Application.stop()`・`Application.setWindowTitle(_:)`・`Application.setCursorShape(_:)` の扱いは、「まだ決まっていない論点」にある。

### 公開 API の名前と形は SwiftUI に合わせる

- 決定: 公開 API の名前・引数・振る舞いは SwiftUI に合わせる。SwiftUI と同じ名前で振る舞いを変えたものは、`docs/GLOSSARY.md` の「SwiftUI と同じ名前で、振る舞いが違うもの」に書く。
- 理由: TUIKit の型は SwiftUI の名前を採っている。同じ書き方で違う振る舞いになると、警告も無いまま TUIKit アプリが壊れる。表に書いておけば、違いを知ったうえで使える。
- 捨てた案: TUIKit 独自の形にする案（フォーカスを持つ `View` の見た目を、`View.border(focusedStyle:)` のような専用の `View` の拡張メソッドで決めるなど）。上の理由。
- 経緯: #53, #154, #167

### 使う `View` もデモも無い API は入れない

- 決定: SwiftUI にあっても、TUIKit の中に使う `View` も、デモに使う場面も無い API は入れない。今入れていないものは、`@Environment`・`EnvironmentValues`・`ShapeStyle`・`backgroundStyle(_:)`・`focusable`・`defaultFocus`・`onContinuousHover(coordinateSpace:perform:)` など。
- 理由: 振る舞いを決める材料になる使う場面が無く、入れても確かめられない。
- 捨てた案: 記録なし。
- 経緯: #53, #141, #142, #154

### 配色は `View` の拡張メソッドで決め、`View` のイニシャライザで受け取らない

- 決定: 配色は `View.foregroundStyle(_: Color)`・`View.foregroundStyle(_:_:)`・`View.tint(_:)`・`View.background(_:)` で決め、`RenderContext` が内側の `View` へ伝える。`Text`・`ListView`・`TextField`・`ProgressBar`・`Divider`・`Fill` のイニシャライザは色を受け取らない（`View.border(_:color:title:)` の `color:` だけは受け取る）。名前付きの配色（テーマ）の層と、`ApplicationOptions` で配色を受け取る形は入れない。
- 理由: SwiftUI のイニシャライザは色を受け取らない。引数と `View` の拡張メソッドの両方を置くと、同じ配色を書く方法が 2 つになり、どちらが勝つかを覚える必要が出る。
- 捨てた案:
  - `View` のイニシャライザに `Style?` の引数を残す案。上の理由。
  - `Theme` と `ApplicationOptions.theme` を入れる案。役割の集合などに、選んだ根拠が無かった。
  - セカンダリレベルを `brightBlack` に固定する案。Solarized で背景と同じ色になる。
- 経緯: #73, #154

### 入力を止めるかは 1 つの判定で決める

- 決定: `View.sheet(isPresented:content:)` で重ねた `View` の後ろ・`View.disabled(_:)`・ホバーで入力を止めるかは、`FocusIndex.acceptsInput(at:)` の 1 つの判定で決める。`.mouse` は、その位置でいちばん手前に `Buffer` へ書き込んだ `View` に当て、下の `View` へ抜けない。
- 理由: 判定を別々に並べると、片方を書き忘れたとき、シートの後ろでは止まるが `View.disabled(_:)` では止まらない入力が生まれる。
- 捨てた案: `View.disabled(_:)` に `true` を渡した `View` へのクリックを、下の `View` へ通す案（tview の振る舞い）。重ねて描く規則と食い違う。
- 経緯: #53, #141, #142

### 非同期の処理は `View.task(_:)` で書き、`Application.run()` は `Task` の終わりを待たない

- 決定: 非同期の処理は `View.task(_:)` で書く。`Task` は、`ViewNode` が捨てられたら打ち切る。`Application.run()` は `Task` の終わりを待たずに戻る。`Effect` のように非同期の処理を宣言する型、外から値を送る口、起動・終了・一時停止・再開を知らせるメソッドは入れない。
- 理由: 終わりを待つと、打ち切りに応じない `Task` があるときに Ctrl+C でも終われなくなる。SwiftUI の `View.task` も終わりを待たない。終了を知らせるメソッドは `TerminalApp.isFinished` と二重になり、ほかを知らせるメソッドは必要を示す具体例が無い。
- 捨てた案:
  - `Effect` で宣言する案。async 関数で書けることを独自の型でなぞるだけになる。
  - 起動時に値を送る口を渡すメソッドを置く案。始めた `Task` を `Application` が知らないので打ち切れない。
  - `Task` の終わりを待つ案。上の理由。
  - 起動・終了・一時停止・再開を知らせるメソッドを置く案。必要を示す具体例が出たら、改めて決める。
- 経緯: #54, #96

### 起動の入口は `TerminalApp.main()` と `TerminalApp.run()` だけにする

- 決定: 起動の入口は `TerminalApp.main()` と `TerminalApp.run()`（型メソッドとインスタンスメソッド）だけで、起動の手順はインスタンスメソッドの `run()` にだけ置く。
- 理由: TUIKit を使う開発者が `Application` を自分で組み立てると、起動の手順を写すことになり、後から TUIKit に足した手順が届かない。
- 捨てた案: `main()` の中に、起動するかどうかを決めるメソッドを差し込む案。`@main` を別のライブラリが受け持つ場合に使えない。
- 経緯: #146

### 対応する OS は macOS 15 以降と Linux

- 決定: `Package.swift` の `platforms` は `.macOS(.v15)`。POSIX の API を直接使い、Swift から呼び出せない C の API は CTUIShim に置く。どちらか一方の OS にしか無い API に頼らない。
- 理由: macOS 15 にしたのは、`Mutex` で `LoopEventQueue` を、コンパイラの検査を受けた `Sendable` にするため。一方の OS にしか無い API を使うと、もう一方に向けた、検査されないコードが別に残る。
- 捨てた案:
  - macOS 13 のまま、`NSLock` と `@unchecked Sendable` で守る案。並行性検査の指摘を宣言で黙らせることになる。
  - `OSAllocatedUnfairLock` で守る案。Apple の OS にしか無い。
- 経緯: #106, #109

### Swift 6 言語モードでビルドする

- 決定: tools-version 6.0 で、Swift 6 言語モードでビルドする。`swiftLanguageMode(.v5)` や、並行性検査を弱める設定を足さない。
- 理由: 並行性の指摘が warning にとどまると、宣言で消せてしまい、`@MainActor` への隔離で越境を error にした狙いが成り立たない。
- 捨てた案: `swiftLanguageMode(.v5)` で固定する案。tools-version を 6.0 に上げる間の暫定だった。
- 経緯: #106, #109

## まだ決まっていない論点

ここにある論点に当たる変更をするときは、作業を止める（`CONTRIBUTING.md` の「まだ決まっていない論点に当たったとき」）。

### パッケージの依存を持たないことを方針にするか

- 当たる変更: `Package.swift` に `dependencies` を足す。Swift Macros を入れる。
- 補足: 今は依存が無く、`CLAUDE.md` の冒頭に「依存ライブラリなし」とある。方針として決めた記録と理由は無い。
- 経緯: #100

### README に、機能ごとの説明を置くか

- 当たる変更: README に、機能や `View` の拡張メソッドの説明を足す。README から既存の説明を消す。
- 補足: README を概要・導入・最小例・デモ・動作環境・ライセンスに絞り、宣言ごとの説明を DocC に置くと決めた後に、配色と `View.disabled(_:)` の段落が README に足されている。
- 経緯: #133

### `TerminalApp.handle(_:)` や `View.onKeyPress(_:action:)` のクロージャから、クリップボードへのコピーと一時停止をどう行うか

- 当たる変更: `ApplicationContext` を public にする。`TerminalApp.handle(_:)` の引数を変える。`Application.copyToClipboard(_:limit:)`・`Application.suspend()` に新しい経路を足す。`@Environment` に当たるものを入れる。
- 選択肢: 非 generic の型を `TerminalApp.handle(_:)` の引数で渡す。`@Environment` に当たるプロパティラッパーで `View` に渡し、描画の中で呼び出しても無視する。
- 補足: 非 generic にすること、TUIKit を使う開発者に保持させないこと、描画の中からは呼び出せないことは決まっている。
- 経緯: #103

### ウィンドウタイトルとカーソル形状を、TUIKit アプリはどこで宣言するか

- 当たる変更: `TerminalApp` に `windowTitle`・`cursorShape` のような要件を足す。`View.windowTitle(_:)` のような `View` の拡張メソッドを足す。`Application.setWindowTitle(_:)`・`Application.setCursorShape(_:)`・`Application.stop()` を消すか変える。
- 選択肢: `TerminalApp` の要件にする。`View` の拡張メソッドにする。
- 補足: 命令ではなく宣言にし、`Application` が値を読んで、変わったときだけ端末エミュレータへ送ることは決まっている。
- 経緯: #98, #105

### `Application.run()` が戻った後に、シグナルハンドラを元に戻すか

- 当たる変更: `SignalWatcher`・`CrashRestorer` が登録したシグナルハンドラを、`Application.run()` の終わりで戻すコードを足す。
- 補足: 戻すと、SIGPIPE など TUIKit と関係のない振る舞いまで変わるという懸念だけが書かれている。

### `View` の内側へ伝わる値を、TUIKit を使う開発者に公開するか

- 当たる変更: `RenderContext` に public のプロパティを足す。`ViewEnvironment` を public にする。`@Environment`・`EnvironmentValues`・`ShapeStyle` を入れる。外側で決めた色、フォーカスを持つか、`View.disabled(_:)` で外されたかを `PrimitiveView` から取得する手段を足す。

### `PrimitiveView` がフォーカスを受け取り、端末エミュレータのカーソルを置く方法をどうするか

- 当たる変更: `focusable`・`defaultFocus` に当たるものを入れる。`TerminalApp.cursorPosition` を消す。
- 補足: `TerminalApp.cursorPosition` を消すかは、この方法を入れるときに決める。

### ボタン・チェックボックスなどの `View` の値を、どこに置くか

- 当たる変更: ボタン・チェックボックス・ラジオボタン・セレクトの `View` を足す。`ListState` のようなクラスを足す。
- 選択肢: `ListState`・`TextFieldState` と同じくクラスにする。`TerminalApp` に準拠する型が値を持ち、`Binding` で渡す。
- 補足: ボタンを押したときにフォーカスを移すかも決まっていない。
- 経緯: #70

### スクロール位置と選択位置を持つクラスを、`ListState` と共通にするか

- 当たる変更: スクロールを持つ共通のクラスを足す。`ListState` を一般化する。表・ツリービュー・タブビューの値を持つクラスを足す。
- 経緯: #57, #66, #68, #69

### 任意の `View` をスクロールさせるとき、画面に収まらない部分をどう切り出すか

- 当たる変更: スクロールする `View` やスクロールバーを足す。`Buffer`・`RenderContext` に、原点のずれや範囲の切り取りを足す。
- 選択肢: 別の `Buffer` へ描いて写す。描くときに原点をずらし、範囲の外を `Buffer` に捨てさせる。
- 経緯: #57

### ホイールに表示位置と選択位置のどちらを割り当てるかを、TUIKit アプリが選べるようにするか

- 当たる変更: `ListState.handle(_:)` のホイールの扱いを変える。`ListState` にホイールの割り当てを選ぶプロパティを足す。
- 選択肢: `ListState` に列挙型のプロパティを置く。`ListState.handle(_:)` を通さずにスクロールのメソッドを呼び出す使い方を正式にする。選べるようにせず、理由を書いておく。
- 経緯: #81

### `ListView` の行に任意の `View` を置くとき、どういう形にするか

- 当たる変更: `ListView` に `ViewBuilder` のクロージャを受け取るイニシャライザを足す。行の高さを 1 より大きくできるようにする。
- 選択肢: 行の高さを 1 に固定するか、複数行を許すか。選択された行であることを、行の `View` へどう伝えるか。
- 経緯: #56, #66

### 1 つの `Text` の中で範囲ごとにスタイルを変えるとき、どう表すか

- 当たる変更: `Text` が持つ値を変える。`TextWrapping` の戻り値を変える。スタイルの付いた文字列の型を足す。`Text` どうしの連結を入れる。
- 選択肢: `Text` に範囲と `Style` の組の配列を持たせる。新しい型を作る。`Text` どうしを `+` で連結する。
- 経緯: #55, #63, #75

### OSC 8 のハイパーリンクの行き先を、どこに持つか

- 当たる変更: `Cell` にプロパティを足す。`Renderer` が書き出すバイト列にリンクの開始と終了を足す。リンクを付ける `View` の拡張メソッドを足す。
- 選択肢: `Cell` に行き先の文字列を持たせる。番号で持ち、番号と行き先の対応を `Buffer` に置く。
- 経緯: #63

### 比率・最小・最大の制約と `Grid` を、どう表すか

- 当たる変更: `LayoutTraits` や `StackLayout` を変える。`Grid` を足す。`View.frame(width:height:horizontalAlignment:verticalAlignment:)` に最小・最大の引数を足す。表の列の幅を決める API を足す。
- 選択肢: `LayoutTraits` に最小と最大の `Size` を足すか、`View` の拡張メソッドで渡すか。比率を `LayoutTraits.horizontalFlex`・`LayoutTraits.verticalFlex` の重みで表すか、別に置くか。
- 補足: 今の `LayoutTraits` を置き換えず、上に足すことは決まっている。
- 経緯: #58, #66

### 複数行のテキストエディタの値を、どう持つか

- 当たる変更: 複数行のテキストエディタの `View` を足す。`TextFieldState` が持つ値を変える。
- 選択肢: 行の配列で持つか、1 本の配列と改行の位置で持つか。画面の幅で折り返すか。`TextFieldState` を複数行に広げるか、別の型にするか。
- 経緯: #67

### ツリービューは、階層を持つ値をどう受け取るか

- 当たる変更: ツリービューと、その値を持つクラスを足す。
- 選択肢: 項目の配列を入れ子で持つ。ある項目の下の項目を返す関数を受け取り、開いたときに取得する。
- 経緯: #68

### タブビューで、見出しが幅に収まらないときと、切り替えのキーをどうするか

- 当たる変更: タブビューを足す。
- 選択肢: 見出しを省略するか、横にスクロールさせるか。Tab はフォーカスの移動に使っているので、切り替えのキーを Ctrl+PageUp・Ctrl+PageDown などにするか。
- 経緯: #69

### 画面を壊さずにログを出すには、どこへ出すか

- 当たる変更: ログの型を足す。`ApplicationOptions` に出力先を足す。標準エラー出力（fd 2）を差し替える。
- 選択肢: ファイルへ書く。標準エラー出力を差し替える。溜めておき、画面の中に表示する。`Terminal.restore()` の後にまとめて書き出す。
- 経緯: #74

### 画面の中の文字列を選んでコピーするとき、選択範囲をどう決めるか

- 当たる変更: 選択範囲を持つ型を足す。ドラッグを受け取る。`Buffer` から範囲の文字列を取り出すメソッドを足す。
- 選択肢: 行の単位で切り出すか、矩形で切り出すか。選択範囲を `TextAttributes.reverse` で描くか、別のスタイルにするか。キーボードで選べるようにするか。
- 経緯: #75

### 端末エミュレータの色数を判定し、色を減らすとき、どこで減らすか

- 当たる変更: 環境変数 `COLORTERM`・`TERM` を読む。`ApplicationOptions` に色数を足す。`Color` から SGR への変換を変える。
- 選択肢: `Style` が SGR を作るところで減らすか、`Renderer` で減らすか。判定結果を TUIKit アプリが上書きする形。環境変数 `NO_COLOR` に従うか。
- 経緯: #59

### 画像を表示するとき、どの方式に対応し、何を受け取るか

- 当たる変更: 画像を表示する `View` を足す。`Cell` のピクセル数を端末エミュレータに問い合わせる。`Renderer` に、差分を取らない範囲を足す。
- 選択肢: Sixel・kitty graphics protocol・iTerm2 のどれに対応するか。ピクセルの配列だけを受け取るか、画像ファイルを読み込むところまで行うか。
- 経緯: #65

### 公開 API の名前に使う `Column` を、何に置き換えるか

- 当たる変更: `TextFieldState.cursorColumn(ambiguous:)`・`BorderStyle.fitsInSingleColumn(ambiguous:)` の名前を変える。`Cell` の数や横方向の位置を表す、新しい公開の名前を付ける。
- 補足: `docs/GLOSSARY.md` の書き方と、英語の名前の対応を先に決める。
- 経緯: #136, #137
