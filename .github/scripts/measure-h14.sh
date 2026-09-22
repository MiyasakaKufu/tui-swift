#!/bin/bash
# H14 の計測。`Terminal.deinit` が何を担っているか。
set -u

git config --global --add safe.directory "$PWD"
git checkout HEAD -- Sources Package.swift

echo "## H14: deinit が担っている仕事" >> summary.txt

run_case() {
  local label="$1"
  rm -rf .build
  swift test --filter DeinitNecessityTests > h14.log 2>&1
  echo "### $label" >> summary.txt
  echo "  終了値: $?" >> summary.txt
  grep -o 'H14: .*' h14.log | sed 's/^/    /' >> summary.txt
  grep -o "Test Case '[^']*' \(passed\|failed\|skipped\)" h14.log | sort -u | sed 's/^/    /' >> summary.txt
}

run_case "deinit {}（現ブランチ）"

perl -0pi -e 's/    \/\/ deinit はアクタに隔離できないため.*?\n    \/\/ 設計で解く必要がある箇所。ここでは計測のために空にする。\n    deinit \{\}/    deinit { restore() }/s' Sources/TUIKit/Terminal/Terminal.swift
if ! grep -q 'deinit { restore() }' Sources/TUIKit/Terminal/Terminal.swift; then
  echo "  deinit を戻せなかった" >> summary.txt
  exit 1
fi
run_case "deinit { restore() }（main の形）"
