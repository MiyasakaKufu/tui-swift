# 開発の指針

DocC・コメント・コミットログは日本語で書く。適用範囲は `Sources` と `Tests` の両方。

## 情報の置き場所

[t-wada 氏の整理](https://x.com/t_wada/status/904916106153828352)に従う。

| 種類 | 置き場所 |
| --- | --- |
| How（どう実現しているか） | コード |
| What（何をするか） | テストコード |
| Why（なぜこの実装にしたか） | コミットログ |
| Why not（なぜそうしないのか） | コードコメント（`//`） |

媒体ごとに寿命・見える範囲・検証されるかが違うので、それに合わせて置き場所を決める。テストに書いた振る舞いは嘘になれば CI が落ちるが、コメントに書いた振る舞いは嘘になっても誰も気づかない。実装を選んだ経緯は `git log` / `git blame` から辿れるので、コード中に写さない。

DocC は上の 4 分類と別の軸にある。`//` が保守者に向くのに対し、`///` は利用者に向く成果物で、API の一部である。

## DocC（`///`）の書き方

[Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) と [Writing symbol documentation in your source files](https://developer.apple.com/documentation/xcode/writing-symbol-documentation-in-your-source-files) に従う。

### 書く対象

public なすべての宣言に書く。非 public には必須としないが、書く場合は同じ書式に従う。

### 構造と順序

```swift
/// 要約。
///
/// 追加の説明（任意）。
///
/// - Parameters:
///   - x: ...
/// - Returns: ...
/// - Throws: ...
/// - Note: ...
```

地の文の説明は要約の直後に置き、`- Parameters:` より後ろへ置かない。コールアウト（`- Note:` など）は `- Parameters:` / `- Returns:` の後ろに置く。

`///` と宣言の間に `//` を挟まない。挟むと DocC が宣言に結び付かない。`//` を書くなら `///` の上に置く。

### 要約

1 文の断片をピリオドで終える。完全な文にしない。宣言の種類ごとに書き出しを揃える。

| 宣言 | 何を書くか |
| --- | --- |
| 関数・メソッド | 何を **する** か、何を **返す** か。null effect と `Void` の返りは省く |
| subscript | 何に **アクセス** するか |
| イニシャライザ | 何を **作る** か |
| 型・プロパティ・その他 | その実体が **何である** か |

### パラメーターと返り値

パラメーターがあれば、すべてに説明を書く。各パラメーターを独立して説明し、目的と、必要なら許容値の範囲を書く。

記法は `- Parameters:` のネスト形に統一する。引数が 1 つでも単数形の `- Parameter x:` は使わない（引数が増えたときに書き換えが要らないため）。並べる順序は宣言に合わせ、名前は DocC が参照する内部名（`_ event: InputEvent` なら `event`）を使う。

返り値があれば `- Returns:` を書く。エラーを投げるなら `- Throws:` を書く。subscript は何にアクセスするかを要約で述べるので、`- Returns:` は求めない。

### 条件と注意点

地の文ではなくコールアウト記法を使う。

| 内容 | 記法 |
| --- | --- |
| 呼び出し前に満たすべき条件 | `- Precondition:` |
| 呼び出し後に保証される状態 | `- Postcondition:` |
| 常に保たれる条件 | `- Invariant:` |
| 知らないと誤用する挙動 | `- Note:` |
| 誤ると壊れる、失われる | `- Warning:` |
| 計算量 | `- Complexity:` |

使えるコールアウトは [swift/docs/DocumentationComments.md](https://github.com/apple/swift/blob/main/docs/DocumentationComments.md) にある次のもの。

> Attention, Author, Authors, Bug, Complexity, Copyright, Date, Experiment, Important, Invariant, Note, Postcondition, Precondition, Remark, Remarks, Requires, See, Since, Todo, Version, Warning

### 書かないもの

- 実装の手順（→ `//`）
- その実装を選んだ理由（→ コミットログ）

## コメント（`//`）の書き方

書いてよいのは次の 2 つ。

**1. Why not** — 「こう直したくなるが、そうすると壊れる」という、これからコードを直す人への警告。

```swift
// 端末は全角文字を半分だけ描けない。半端に残った桁を文字で埋めてはいけない。
while x < region.maxX {
```

**2. 外部仕様・規格の典拠** — なぜその判定や定数なのかを支える根拠。コードにもテストにも現れず、利用者向けではないので DocC にも置けない。

```swift
// 異体字セレクタ 16 が付いていれば絵文字表示（全角）。
```

コードを言い換えただけのコメントは書かない。

`// MARK:` は区切り記号であり、この規則の対象外とする。

## コミットログの書き方

Why を書く。なぜこの実装にしたか、どの案を検討して捨てたか。捨てた案は、書かなければコードに痕跡が残らない。

## 確認

```sh
swift build
swift test
```

`DocumentationStyleTests` が、この指針のうち機械的に判定できるものを検査する。

- public な宣言に DocC があるか
- 単数形の `- Parameter` を使っていないか
- すべての引数に説明があり、順序が宣言と一致しているか。宣言にない引数の説明が残っていないか
- 返り値に `- Returns:`、`throws` に `- Throws:` があるか
- `///` と宣言の間に `//` が挟まっていないか

要約の書き出し、コールアウトの選び方、コードを言い換えただけのコメントは機械的に判定できない。レビューで見る。
