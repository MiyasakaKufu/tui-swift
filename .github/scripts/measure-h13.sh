#!/bin/bash
# H13 の計測。`deinit` の中から `self` に触ると参照数が増えて不安定になるか。
set -u

git config --global --add safe.directory "$PWD"

# H11 の計測が Sources/TUIKit と Package.swift を入れ替えているので、ブランチの形へ戻す。
git checkout HEAD -- Sources Package.swift

echo "## H13: deinit の中から self に触る" >> summary.txt

# 計測用の実行ファイルを差し込む。
anchor='        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),'
if [ "$(grep -c -F "$anchor" Package.swift)" -ne 1 ]; then
  echo "  Package.swift に差し込み口が無い" >> summary.txt
  exit 1
fi
awk '
  { print }
  /^        \.executableTarget\(name: "TUIDemo", dependencies: \["TUIKit"\]\),$/ {
    print "        .executableTarget(name: \"DeinitProbe\"),"
  }
' Package.swift > Package.swift.new
mv Package.swift.new Package.swift

echo "### 検査なし" >> summary.txt
swift run DeinitProbe > h13.log 2>&1
echo "  終了値: $?" >> summary.txt
sed 's/^/  /' h13.log >> summary.txt

echo "### アドレスサニタイザあり" >> summary.txt
rm -rf .build
swift run --sanitize=address DeinitProbe > h13-asan.log 2>&1
echo "  終了値: $?" >> summary.txt
sed 's/^/  /' h13-asan.log | head -40 >> summary.txt

# 本物の Terminal で、元の deinit { restore() } を戻してテスト一式を走らせる。
echo "### Terminal の deinit を戻してテスト一式（サニタイザあり）" >> summary.txt
git checkout Package.swift
perl -0pi -e 's/    \/\/ deinit はアクタに隔離できないため.*?\n    \/\/ 設計で解く必要がある箇所。ここでは計測のために空にする。\n    deinit \{\}/    deinit { restore() }/s' Sources/TUIKit/Terminal/Terminal.swift
if grep -q 'deinit { restore() }' Sources/TUIKit/Terminal/Terminal.swift; then
  echo "  deinit を戻した" >> summary.txt
else
  echo "  deinit を戻せなかった" >> summary.txt
  exit 1
fi
rm -rf .build
swift test --sanitize=address > h13-test.log 2>&1
echo "  終了値: $?" >> summary.txt
echo "  ERROR: AddressSanitizer の行:" >> summary.txt
grep -c 'ERROR: AddressSanitizer' h13-test.log | sed 's/^/    /' >> summary.txt
grep -A 12 'ERROR: AddressSanitizer' h13-test.log | head -30 | sed 's/^/    /' >> summary.txt
echo "  落ちたテスト:" >> summary.txt
grep -o "Test Case '[^']*' failed" h13-test.log | sort -u | head -10 | sed 's/^/    /' >> summary.txt
