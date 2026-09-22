"""計測用ターゲットを Package.swift へ差し込む。"""
import pathlib
import sys

mode = sys.argv[1]
settings = '' if mode == 'none' else ',\n            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]'
path = pathlib.Path("Package.swift")
source = path.read_text()
anchor = '        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),'
addition = (
    f'{anchor}\n'
    f'        .target(\n'
    f'            name: "InstabilityProbe",\n'
    f'            dependencies: ["TUIKit"]{settings}\n'
    f'        ),'
)
assert source.count(anchor) == 1
path.write_text(source.replace(anchor, addition))
print(f"InstabilityProbe を追加（strict concurrency: {mode}）")
