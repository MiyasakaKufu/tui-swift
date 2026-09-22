#!/bin/bash
# H11 の計測。同じ計測用コードを 3 通りの構成でビルドし、診断の件数を比べる。
set -u

count_probe_diagnostics() {
  local label="$1"
  swift build --target InstabilityProbe 2>&1 | sed 's#.*/tui-swift/##' > h11.log || true
  local errors warnings
  errors=$(grep -c "^Sources/InstabilityProbe/.*error:" h11.log || true)
  warnings=$(grep -c "^Sources/InstabilityProbe/.*warning:" h11.log || true)
  echo "### $label" >> summary.txt
  echo "  error: $errors / warning: $warnings" >> summary.txt
  grep -o "^Sources/InstabilityProbe/Probe.swift:[0-9]*:[0-9]*: \(error\|warning\)" h11.log \
    | sort -u | sed 's/^/    /' >> summary.txt
}

echo "## H11: 別の実行文脈から UI の状態に触るコードの診断" >> summary.txt

# 1. 案 B（現ブランチ。隔離あり）
count_probe_diagnostics "案 B（隔離あり・strict concurrency あり）"

# 2. 案 A（main の形）+ strict concurrency
# 取り出しに失敗したまま進めてはいけない。3 つの構成が同じ数字になり、比較にならない。
{
  echo "--- 取り出しの診断 ---"
  git rev-parse --is-shallow-repository
  git rev-parse origin/main 2>&1 | head -1
  git fetch --no-tags origin main 2>&1 | tail -3
  git checkout origin/main -- Sources/TUIKit Package.swift 2>&1 | tail -3
} >> summary.txt
if grep -q 'TUIActor' Sources/TUIKit/App/Component.swift; then
  echo "main の形になっていない" >> summary.txt
  exit 1
fi
python3 .github/scripts/inject-probe-target.py complete
count_probe_diagnostics "案 A（隔離なし・strict concurrency あり）"

# 3. 案 A（main の形）、検査なし
git checkout origin/main -- Package.swift
python3 .github/scripts/inject-probe-target.py none
count_probe_diagnostics "案 A（隔離なし・strict concurrency なし）"
