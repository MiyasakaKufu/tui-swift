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

## 書き方の指針

DocC・コメント・コミットログは `CONTRIBUTING.md` に従う。コードやコメントを書く前に読むこと。

`Tests/TUIKitTests/DocumentationStyleTests.swift` が、指針のうち機械的に判定できる分を検査する。
コメントや DocC を直したら `swift test` を通す。
