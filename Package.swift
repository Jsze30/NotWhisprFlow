// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "WhisperFlow",
            path: "Sources/WhisperFlow"
        ),
        .testTarget(name: "WhisperFlowTests", dependencies: ["WhisperFlow"])
    ]
)
