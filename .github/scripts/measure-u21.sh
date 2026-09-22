#!/bin/bash
# U21 の計測。main の形（deinit { restore() }）でテスト一式をアドレスサニタイザに通す。
# D45（deinit から自分のメソッドを呼ぶことは不安定さを生まない）の裏取り。
#
# 結果がログの末尾に来るよう、最後のステップとして独立させてある。この環境は
# CI のログの末尾しか読めない。
set -u

git config --global --add safe.directory "$PWD"

report() {
  local label="$1" status="$2" log="$3"
  echo "### $label" >> summary.txt
  echo "  終了値: $status" >> summary.txt
  echo "  ビルドの error 行: $(grep -c 'error:' "$log" || true)" >> summary.txt
  grep 'error:' "$log" | grep -v 'ld.gold' | sort -u | head -5 | sed 's#.*/tui-swift/##' | sed 's/^/    /' >> summary.txt
  echo "  ERROR: AddressSanitizer の件数: $(grep -c 'ERROR: AddressSanitizer' "$log" || true)" >> summary.txt
  grep -A 6 'ERROR: AddressSanitizer' "$log" | head -12 | sed 's/^/    /' >> summary.txt
}

echo "## U21: main の形でテスト一式をサニタイザに通す" >> summary.txt
# 本物の Terminal で deinit { restore() } が生きている形は main 側。案 B のブランチでは
# restore() が @TUIActor に隔離されているので deinit から呼べずコンパイルできない。
git checkout HEAD -- Package.swift
git fetch --no-tags origin main >/dev/null 2>&1
# git checkout は main に無いファイルを消さない。ブランチだけにあるテストが残り、
# main の Sources に無い API を参照して 113 件の error になっていた。消してから取り出す。
rm -rf Sources Tests
git checkout origin/main -- Sources Tests Package.swift
# main の deinit は 3 行に分かれている。1 行で書かれている前提にしない。
if ! grep -A 1 'deinit {' Sources/TUIKit/Terminal/Terminal.swift | grep -q 'restore()'; then
  echo "  main の deinit を取り出せなかった" >> summary.txt
  exit 1
fi
rm -rf .build
swift test --sanitize=address > h13-test.log 2>&1
report "main の形（deinit { restore() }）でテスト一式（サニタイザあり）" "$?" h13-test.log
echo "  走ったテスト: $(grep -oE '[0-9]+ tests? passed|^Executed [0-9]+ tests' h13-test.log | tail -1)" >> summary.txt
echo "  落ちたテスト:" >> summary.txt
grep -o "Test Case '[^']*' failed" h13-test.log | sort -u | head -10 | sed 's/^/    /' >> summary.txt
# 終了値が 1 でも落ちたテストが 0 件のことがある。理由を出す。
echo "  失敗・中断の行:" >> summary.txt
grep -iE 'failed|fatal|signal|abort|Segmentation|LeakSanitizer|SUMMARY' h13-test.log \
  | grep -v 'ld.gold' | sort -u | cut -c1-160 | head -8 | sed 's/^/    /' >> summary.txt
echo "  ログの末尾:" >> summary.txt
tail -6 h13-test.log | cut -c1-160 | sed 's/^/    /' >> summary.txt
