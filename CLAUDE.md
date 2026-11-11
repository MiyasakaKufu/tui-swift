# CLAUDE.md

依存ライブラリなしのターミナル UI ライブラリ。`Sources/TUIKit` が本体、`Sources/TUIDemo` がデモ、
`Sources/CTUIShim` は Swift から直接呼べない C の API（可変長引数の `ioctl`、
共用体を含む `struct sigaction`）のための C シム。

## コマンド

```sh
swift build
swift test
swift run tui-demo
```

## 方針

`docs/POLICY.md` が、これからの変更が従う方針と、まだ決まっていない設計の論点をまとめている。作業を始める前に、
触れる範囲の項目を読むこと。まだ決まっていない論点に当たったときにすることは、`CONTRIBUTING.md` の「方針」にある。

コードや文書を変えた差分は、コミットする前に `policy-review` スキルを通す。

## 書き方の指針

DocC・コメント・コミットログは `CONTRIBUTING.md` に従う。コードやコメントを書く前に読むこと。

`Tests/TUIKitTests/DocumentationStyleTests.swift` が、指針のうち機械的に判定できる分を検査する。
コメントや DocC を直したら `swift test` を通す。

`swift test` が見るのは書式だけなので、中身は `comment-review` スキルで見る。コメントや DocC を
足した・直した差分は、コミットする前にこのスキルを通す。1 か所だけ指摘されたときも、同じ種類が
差分全体に残っていないかを掃き出す。
