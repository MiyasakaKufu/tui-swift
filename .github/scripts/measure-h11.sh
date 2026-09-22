#!/bin/bash
# H11 の計測。同じ計測用コードを 3 通りの構成でビルドし、診断の件数を比べる。
set -u

# コンテナの中では git の所有者検査に引っかかる。ここを通さないと取り出しができない。
git config --global --add safe.directory "$PWD"

count_probe_diagnostics() {
  local label="$1"
  local status
  swift build --target InstabilityProbe > h11.raw 2>&1
  status=$?
  sed 's#.*/tui-swift/##' h11.raw > h11.log
  local errors warnings other
  errors=$(grep -c "^Sources/InstabilityProbe/.*error:" h11.log || true)
  warnings=$(grep -c "^Sources/InstabilityProbe/.*warning:" h11.log || true)
  # 計測用コード以外のエラー。0 件が「診断なし」なのか「別の理由でビルドが止まった」のかを
  # 区別できないままにしない。
  other=$(grep "error:" h11.log | grep -cv "^Sources/InstabilityProbe/" || true)
  echo "### $label" >> summary.txt
  echo "  swift build の終了値: $status（計測用コード以外の error 行: $other）" >> summary.txt
  echo "  Probe.swift をコンパイルしたか: $(grep -c 'Compiling InstabilityProbe' h11.log)" >> summary.txt
  echo "  error: $errors / warning: $warnings" >> summary.txt
  grep -o "^Sources/InstabilityProbe/Probe.swift:[0-9]*:[0-9]*: \(error\|warning\)" h11.log \
    | sort -u | sed 's/^/    /' >> summary.txt
  if [ "$other" -ne 0 ]; then
    echo "  計測用コード以外のエラー:" >> summary.txt
    grep "error:" h11.log | grep -v "^Sources/InstabilityProbe/" | sort -u | head -5 | sed 's/^/    /' >> summary.txt
  fi
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
