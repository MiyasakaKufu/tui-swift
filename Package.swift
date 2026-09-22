// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "swift-tui",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TUIKit", targets: ["TUIKit"]),
        .executable(name: "tui-demo", targets: ["TUIDemo"]),
    ],
    targets: [
        .target(name: "CTUIShim"),
        // 言語モードは当面 v5 に留める。tools-version 6.0 の既定は v6 で、並行性検査が
        // error になる。切り替えるのは、非隔離のグローバル可変状態を直した後。
        .target(name: "TUIKit", dependencies: ["CTUIShim"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"], swiftSettings: [.swiftLanguageMode(.v5)]),
        // 製品コードから参照できてしまうため、ライブラリ本体のターゲットには混ぜない。
        // glibc は posix_openpt などを機能テストマクロで隠すため、Linux では _GNU_SOURCE を立てる。
        .target(
            name: "CTUITestSupport",
            path: "Tests/CTUITestSupport",
            cSettings: [.define("_GNU_SOURCE", .when(platforms: [.linux]))]
        ),
        .testTarget(
            name: "TUIKitTests",
            dependencies: ["TUIKit", "CTUITestSupport"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
