// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "twen",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "TwenCore"),
        // The app lives in a library target so Xcode previews work: the preview
        // engine can't preview code in executable SwiftPM targets (needs
        // ENABLE_DEBUG_DYLIB, which SwiftPM executables don't support).
        .target(name: "TwenApp", dependencies: ["TwenCore"], path: "Sources/twen"),
        .executableTarget(name: "twen", dependencies: ["TwenApp"], path: "Sources/twenMain"),
        .testTarget(name: "TwenCoreTests", dependencies: ["TwenCore"]),
    ]
)
