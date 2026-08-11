// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "twen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TwenCore"),
        .executableTarget(name: "twen", dependencies: ["TwenCore"]),
        .testTarget(name: "TwenCoreTests", dependencies: ["TwenCore"]),
    ]
)
