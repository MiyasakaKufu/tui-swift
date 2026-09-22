#!/bin/bash
# H14 の計測。`Terminal.deinit` が何を担っているか。
set -u

git config --global --add safe.directory "$PWD"
git checkout HEAD -- Sources Tests Package.swift

# H11 の計測用ターゲットはわざと診断が出るコードなので、ここでは外す。
awk -f .github/scripts/strip-probe-target.awk Package.swift > Package.swift.new
mv Package.swift.new Package.swift
rm -rf Sources/InstabilityProbe
if [ "$(grep -c InstabilityProbe Package.swift)" -ne 0 ]; then
  echo "  計測用ターゲットを外せなかった" >> summary.txt
  exit 1
fi

echo "## H14: deinit が担っている仕事" >> summary.txt

run_case() {
  local label="$1" status
  rm -rf .build
  swift test --filter DeinitNecessityTests > h14.log 2>&1
  status=$?
  echo "### $label" >> summary.txt
  echo "  終了値: $status" >> summary.txt
  echo "  ビルドの error 行: $(grep -c 'error:' h14.log || true)" >> summary.txt
  grep 'error:' h14.log | sed 's#.*/tui-swift/##' | sort -u | cut -c1-180 | head -5 | sed 's/^/    /' >> summary.txt
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
