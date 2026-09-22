#!/bin/bash
# H11 の計測。同じ計測用コードを 3 通りの構成でビルドし、診断の件数を比べる。
set -u

# コンテナの中では git の所有者検査に引っかかる。ここを通さないと取り出しができない。
git config --global --add safe.directory "$PWD"

# 計測用ターゲットを Package.swift へ差し込む。swift:6.0 のコンテナには python3 が無い。
inject_probe_target() {
  local mode="$1" settings=""
  if [ "$mode" = "complete" ]; then
    settings=',
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]'
  elif [ "$mode" = "escape" ]; then
    settings=',
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete", "-DPROBE_ESCAPE"])]'
  fi
  local anchor='        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),'
  if [ "$(grep -c -F "$anchor" Package.swift)" -ne 1 ]; then
    echo "  Package.swift に差し込み口が無い" >> summary.txt
    exit 1
  fi
  awk -v settings="$settings" '
    { print }
    /^        \.executableTarget\(name: "TUIDemo", dependencies: \["TUIKit"\]\),$/ {
      print "        .target("
      print "            name: \"InstabilityProbe\","
      printf "            dependencies: [\"TUIKit\"]%s\n", settings
      print "        ),"
    }
  ' Package.swift > Package.swift.new
  mv Package.swift.new Package.swift
  if [ "$(grep -c 'name: "InstabilityProbe"' Package.swift)" -ne 1 ]; then
    echo "  差し込みに失敗した" >> summary.txt
    exit 1
  fi
}

count_probe_diagnostics() {
  local label="$1"
  local status
  # 構成を変えたのにキャッシュで素通りすると、0 件が「診断なし」に見える。
  rm -rf .build
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
  # 件数だけでは案 A と案 B を判別できない。何を指摘しているかを出す。
  grep "^Sources/InstabilityProbe/Probe.swift:[0-9]*:[0-9]*: \(error\|warning\):" h11.log \
    | sort -u | cut -c1-200 | sed 's/^/    /' >> summary.txt
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
inject_probe_target complete
count_probe_diagnostics "案 A（隔離なし・strict concurrency あり）"

# 3. 案 A（main の形）、検査なし
git checkout origin/main -- Package.swift
inject_probe_target none
count_probe_diagnostics "案 A（隔離なし・strict concurrency なし）"

# 4. 案 A（main の形）+ strict concurrency + 型の側に Sendable を宣言
# H12。案 A で出る診断が、危険な参照をそのまま残して消せるかを見る。
git checkout origin/main -- Package.swift
inject_probe_target escape
count_probe_diagnostics "案 A（隔離なし・strict concurrency あり・型に @unchecked Sendable）"
