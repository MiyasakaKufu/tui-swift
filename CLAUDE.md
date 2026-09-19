# CLAUDE.md

依存ライブラリなしのターミナル UI ライブラリ。`Sources/TUIKit` が本体、`Sources/TUIDemo` がデモ、
`Sources/CTUIShim` は可変長引数の `ioctl` を Swift から呼ぶための C シム。

## コマンド

```sh
swift build
swift test
swift run tui-demo
```

## 書き方の指針

DocC・コメント・コミットログは `CONTRIBUTING.md` に従う。要点は次のとおり。

- 日本語で書く。適用範囲は `Sources` と `Tests` の両方。
- How はコード、What はテスト、Why はコミットログ、Why not は `//`。
- `///` は利用者に向く API の一部。public なすべての宣言に書く。
- 引数は `- Parameters:` のネスト形で、宣言と同じ順序ですべて書く。単数形の `- Parameter` は使わない。
  返り値は `- Returns:`、`throws` は `- Throws:`。
- 条件と注意点は地の文ではなくコールアウト（`- Precondition:` `- Postcondition:` `- Note:` `- Warning:` など）。
- `//` は Why not と外部仕様の典拠だけに使う。コードを言い換えただけのコメントは書かない。
  `//` を書くなら `///` の上に置く（間に挟むと DocC が宣言に結び付かない）。
- DocC に実装の手順や、その実装を選んだ理由を残さない。
- コミットログには Why を書く。検討して捨てた案も書く。

`Tests/TUIKitTests/DocumentationStyleTests.swift` が、この指針のうち機械的に判定できる分を検査する。
コメントや DocC を直したら `swift test` を通す。
