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

# 本物の Terminal で deinit { restore() } が生きている形は main 側。案 B のブランチでは
# restore() が @TUIActor に隔離されているので deinit から呼べずコンパイルできない。
git checkout HEAD -- Package.swift
git fetch --no-tags origin main >/dev/null 2>&1
git checkout origin/main -- Sources Package.swift
# main の deinit は 3 行に分かれている。1 行で書かれている前提にしない。
if ! grep -A 1 'deinit {' Sources/TUIKit/Terminal/Terminal.swift | grep -q 'restore()'; then
  echo "  main の deinit を取り出せなかった" >> summary.txt
  exit 1
fi
rm -rf .build
swift test --sanitize=address > h13-test.log 2>&1
report "main の形（deinit { restore() }）でテスト一式（サニタイザあり）" "$?" h13-test.log
echo "  走ったテスト: $(grep -oE '^Executed [0-9]+ tests' h13-test.log | tail -1)" >> summary.txt
echo "  落ちたテスト:" >> summary.txt
grep -o "Test Case '[^']*' failed" h13-test.log | sort -u | head -10 | sed 's/^/    /' >> summary.txt
