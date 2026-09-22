#!/bin/bash
# H13 の計測。`deinit` の中から `self` に触ると参照数が増えて不安定になるか。
set -u

git config --global --add safe.directory "$PWD"

# H11 の計測が Sources/TUIKit と Package.swift を入れ替えているので、ブランチの形へ戻す。
git checkout HEAD -- Sources Package.swift

echo "## H13: deinit の中から self に触る" >> summary.txt

# 生のログは ASan のリンカ警告で数千行になる。要るところだけを出す。
report() {
  local label="$1" status="$2" log="$3"
  echo "### $label" >> summary.txt
  echo "  終了値: $status" >> summary.txt
  echo "  ビルドの error 行: $(grep -c 'error:' "$log" || true)" >> summary.txt
  grep 'error:' "$log" | grep -v 'ld.gold' | sort -u | head -5 | sed 's#.*/tui-swift/##' | sed 's/^/    /' >> summary.txt
  grep -o 'H13: .*' "$log" | sed 's/^/    /' >> summary.txt
  echo "  ERROR: AddressSanitizer の件数: $(grep -c 'ERROR: AddressSanitizer' "$log" || true)" >> summary.txt
  grep -A 6 'ERROR: AddressSanitizer' "$log" | head -12 | sed 's/^/    /' >> summary.txt
}

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

for mode in touch escape; do
  swift run DeinitProbe "$mode" > "h13-$mode.log" 2>&1
  report "検査なし / $mode" "$?" "h13-$mode.log"
done

rm -rf .build
for mode in touch escape; do
  swift run --sanitize=address DeinitProbe "$mode" > "h13-asan-$mode.log" 2>&1
  report "サニタイザあり / $mode" "$?" "h13-asan-$mode.log"
done
