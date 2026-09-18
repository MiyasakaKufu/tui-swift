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
        // テストから疑似端末（pty）を扱うためのシム。ライブラリ本体には含めない。
        .target(name: "CTUITestSupport", path: "Tests/CTUITestSupport"),
        .testTarget(name: "TUIKitTests", dependencies: ["TUIKit", "CTUITestSupport"]),
    ]
)
