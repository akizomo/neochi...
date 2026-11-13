// swift-tools-version: 6.0
import PackageDescription

// アプリの判断ロジック。Apple のフレームワークに依存しないので、Linux でも swift test が通る。
let package = Package(
    name: "NeochiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NeochiCore", targets: ["NeochiCore"])],
    targets: [
        .target(name: "NeochiCore"),
        .testTarget(name: "NeochiCoreTests", dependencies: ["NeochiCore"]),
    ]
)
