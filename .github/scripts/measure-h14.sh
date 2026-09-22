#!/bin/bash
# H14 と H17 の計測。
#
# H14: `Terminal.deinit` が担っている仕事は何か。
# H17: その仕事に代替手法があるか。候補は `atexit(3)` から
#      `CrashRestorer.restoreTerminal()` を呼ぶ形（非隔離で、書き出しと tcsetattr のみ）。
#
# 「現在 deinit が使用されている箇所」は main の形（deinit { restore() }）。案 B の
# ブランチでは restore() が隔離されていて deinit から呼べないので、main で測る。
set -u

git config --global --add safe.directory "$PWD"
# git checkout は main に無いファイルを消さない。消してから取り出す。
rm -rf Sources Tests
git checkout HEAD -- Sources Tests Package.swift
git fetch --no-tags origin main >/dev/null 2>&1
rm -rf Sources Tests
git checkout origin/main -- Sources Tests Package.swift

echo "## H14 / H17: deinit の仕事と代替（main の形で測る）" >> summary.txt

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
  echo "  [$label]" >> summary.txt
  echo "    終了値: $status / ビルドの error 行: $(grep -c 'error:' h14.log || true)" >> summary.txt
  grep 'error:' h14.log | sed 's#.*/tui-swift/##' | sort -u | cut -c1-180 | head -5 | sed 's/^/      /' >> summary.txt
  grep -o 'H14: .*' h14.log | sed 's/^/      /' >> summary.txt
}

empty_deinit() {
  perl -0pi -e 's/    deinit \{\n        restore\(\)\n    \}/    deinit {}/s' Sources/TUIKit/Terminal/Terminal.swift
  if ! grep -q 'deinit {}' Sources/TUIKit/Terminal/Terminal.swift; then
    echo "  deinit を空にできなかった" >> summary.txt
    exit 1
  fi
}

echo "### 1. deinit { restore() }（main のまま）" >> summary.txt
run_case "restore() あり" keep
run_case "restore() せずに捨てる" drop
run_case "子プロセスが restore() せずに終了" exit

echo "### 2. deinit {}（代替なし）" >> summary.txt
empty_deinit
rm -rf .build
run_case "restore() あり" keep
run_case "restore() せずに捨てる" drop
run_case "子プロセスが restore() せずに終了" exit

echo "### 3. deinit {} + atexit から restoreTerminal()" >> summary.txt
awk -f .github/scripts/patch-atexit.awk Sources/TUIKit/Terminal/CrashRestorer.swift > CrashRestorer.new
mv CrashRestorer.new Sources/TUIKit/Terminal/CrashRestorer.swift
if [ "$(grep -c 'installExitHandler' Sources/TUIKit/Terminal/CrashRestorer.swift)" -ne 2 ]; then
  echo "  atexit を仕掛けられなかった" >> summary.txt
  exit 1
fi
rm -rf .build
run_case "restore() あり" keep
run_case "restore() せずに捨てる" drop
run_case "子プロセスが restore() せずに終了" exit

echo "### 4. 案 B のブランチで同じ atexit がコンパイルできるか" >> summary.txt
rm -rf Sources Tests
git checkout HEAD -- Sources Tests Package.swift
awk -f .github/scripts/patch-atexit.awk Sources/TUIKit/Terminal/CrashRestorer.swift > CrashRestorer.new
mv CrashRestorer.new Sources/TUIKit/Terminal/CrashRestorer.swift
awk -f .github/scripts/strip-probe-target.awk Package.swift > Package.swift.new
mv Package.swift.new Package.swift
rm -rf Sources/InstabilityProbe Sources/DeinitProbe Sources/DeinitNecessityProbe
perl -0pi -e 's/    \/\/ deinit はアクタに隔離できないため.*?\n    \/\/ 設計で解く必要がある箇所。ここでは計測のために空にする。\n    deinit \{\}/    deinit {}/s' Sources/TUIKit/Terminal/Terminal.swift
rm -rf .build
swift build --build-tests > h14-b.log 2>&1
echo "  ビルドの終了値: $?" >> summary.txt
echo "  error 行: $(grep -c 'error:' h14-b.log || true)" >> summary.txt
grep 'error:' h14-b.log | sed 's#.*/tui-swift/##' | sort -u | cut -c1-180 | head -5 | sed 's/^/    /' >> summary.txt
swift test > h14-bt.log 2>&1
echo "  テストの終了値: $?" >> summary.txt
echo "  落ちたテスト:" >> summary.txt
grep -o "Test Case '[^']*' failed" h14-bt.log | sort -u | head -5 | sed 's/^/    /' >> summary.txt
