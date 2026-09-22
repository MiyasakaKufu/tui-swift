// swift-tools-version: 5.9

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
        .target(
            name: "TUIKit",
            dependencies: ["CTUIShim"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),
        // H11 の計測。製品には含めない。
        .target(
            name: "InstabilityProbe",
            dependencies: ["TUIKit"],
            swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]
        ),
        // 製品コードから参照できてしまうため、ライブラリ本体のターゲットには混ぜない。
        // glibc は posix_openpt などを機能テストマクロで隠すため、Linux では _GNU_SOURCE を立てる。
        .target(
            name: "CTUITestSupport",
            path: "Tests/CTUITestSupport",
            cSettings: [.define("_GNU_SOURCE", .when(platforms: [.linux]))]
        ),
        .testTarget(name: "TUIKitTests", dependencies: ["TUIKit", "CTUITestSupport"]),
    ]
)
