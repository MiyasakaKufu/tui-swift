#!/bin/bash
# H14 の計測。`Terminal.deinit` が何を担っているか。
#
# 「現在 deinit が使用されている箇所」は main の形（deinit { restore() }）。案 B の
# ブランチでは restore() が隔離されていて deinit から呼べないので、main で測る。
set -u

git config --global --add safe.directory "$PWD"
git checkout HEAD -- Sources Tests Package.swift
git fetch --no-tags origin main >/dev/null 2>&1
git checkout origin/main -- Sources Tests Package.swift

echo "## H14: deinit が担っている仕事（main の形で測る）" >> summary.txt

if ! grep -A 1 'deinit {' Sources/TUIKit/Terminal/Terminal.swift | grep -q 'restore()'; then
  echo "  main の deinit を取り出せなかった" >> summary.txt
  exit 1
fi

# 計測用の実行ファイルを差し込む。
git checkout HEAD -- Sources/DeinitNecessityProbe
anchor='        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),'
if [ "$(grep -c -F "$anchor" Package.swift)" -ne 1 ]; then
  echo "  Package.swift に差し込み口が無い" >> summary.txt
  exit 1
fi
awk '
  { print }
  /^        \.executableTarget\(name: "TUIDemo", dependencies: \["TUIKit"\]\),$/ {
    print "        .executableTarget(name: \"DeinitNecessityProbe\", dependencies: [\"TUIKit\", \"CTUITestSupport\"]),"
  }
' Package.swift > Package.swift.new
mv Package.swift.new Package.swift

run_case() {
  local label="$1" mode="$2" status
  swift run DeinitNecessityProbe "$mode" > h14.log 2>&1
  status=$?
  echo "### $label" >> summary.txt
  echo "  終了値: $status" >> summary.txt
  echo "  ビルドの error 行: $(grep -c 'error:' h14.log || true)" >> summary.txt
  grep 'error:' h14.log | sed 's#.*/tui-swift/##' | sort -u | cut -c1-180 | head -5 | sed 's/^/    /' >> summary.txt
  grep -o 'H14: .*' h14.log | sed 's/^/    /' >> summary.txt
}

run_case "deinit { restore() }（main のまま）/ restore() あり" keep
run_case "deinit { restore() }（main のまま）/ restore() せずに捨てる" drop

# deinit を空にする。
perl -0pi -e 's/    deinit \{\n        restore\(\)\n    \}/    deinit {}/s' Sources/TUIKit/Terminal/Terminal.swift
if ! grep -q 'deinit {}' Sources/TUIKit/Terminal/Terminal.swift; then
  echo "  deinit を空にできなかった" >> summary.txt
  exit 1
fi
rm -rf .build
run_case "deinit {} / restore() あり" keep
run_case "deinit {} / restore() せずに捨てる" drop
