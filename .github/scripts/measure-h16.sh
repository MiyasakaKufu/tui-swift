#!/bin/bash
# H16 の計測。案 B のアクタを専用の `@TUIActor` から `@MainActor` へ替えても成り立つか。
set -u

git config --global --add safe.directory "$PWD"
git checkout HEAD -- Sources Tests Package.swift

# H11 の計測用ターゲットはわざと診断が出るコードなので、ここでは外す。外さないと
# その 6 件を「@MainActor に替えたせいのエラー」と読み違える。
awk -f .github/scripts/strip-probe-target.awk Package.swift > Package.swift.new
mv Package.swift.new Package.swift
rm -rf Sources/InstabilityProbe
if [ "$(grep -c InstabilityProbe Package.swift)" -ne 0 ]; then
  echo "  計測用ターゲットを外せなかった" >> summary.txt
  exit 1
fi

echo "## H16: 隔離先を @MainActor にする" >> summary.txt

echo "  替える前の @TUIActor の箇所: $(grep -rn '@TUIActor' Sources Tests | wc -l)" >> summary.txt

# 専用アクタを捨てて @MainActor に替える。
rm Sources/TUIKit/App/TUIActor.swift
grep -rl '@TUIActor' Sources Tests | while read -r file; do
  sed -i 's/@TUIActor/@MainActor/g' "$file"
done
# H5 により @main は @MainActor を特別扱いするので、入り直しの一段が要らない。
sed -i 's/^    nonisolated public static func main() async {/    public static func main() async {/' Sources/TUIKit/App/TerminalApp.swift
sed -i '/^    \/\/ @main は隔離の付いた main() を受け付けない/,+1d' Sources/TUIKit/App/TerminalApp.swift

echo "  替えた後の @TUIActor の箇所: $(grep -rn '@TUIActor' Sources Tests | wc -l)" >> summary.txt
echo "  main() の nonisolated が消えたか: $(grep -c 'nonisolated public static func main' Sources/TUIKit/App/TerminalApp.swift) 件残り" >> summary.txt

rm -rf .build
swift build --build-tests > h16-build.log 2>&1
echo "  ビルドの終了値: $?" >> summary.txt
sed 's#.*/tui-swift/##' h16-build.log > h16-tidy.log
echo "  error 行: $(grep -c 'error:' h16-tidy.log || true)" >> summary.txt
grep -o '^\(Sources\|Tests\)/[^:]*:[0-9]*:[0-9]*: error: .*' h16-tidy.log | sort -u | cut -c1-180 | head -10 | sed 's/^/    /' >> summary.txt
echo "  warning 行: $(grep -c 'warning:' h16-tidy.log || true)" >> summary.txt

swift test > h16-test.log 2>&1
echo "  テストの終了値: $?" >> summary.txt
grep -oE '^Executed [0-9]+ tests[^.]*\.' h16-test.log | tail -1 | sed 's/^/    /' >> summary.txt
echo "  落ちたテスト:" >> summary.txt
grep -o "Test Case '[^']*' failed" h16-test.log | sort -u | head -10 | sed 's/^/    /' >> summary.txt
