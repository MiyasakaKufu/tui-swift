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
        .target(name: "TUIKit", dependencies: ["CTUIShim"]),
        .executableTarget(name: "TUIDemo", dependencies: ["TUIKit"]),
        // テストからだけ使う C の補助（疑似端末の操作）。
        .target(name: "CTUITestSupport", path: "Tests/CTUITestSupport"),
        .testTarget(name: "TUIKitTests", dependencies: ["TUIKit", "CTUITestSupport"]),
    ]
)
