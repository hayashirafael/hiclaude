// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HiClaude",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "HiClaude", path: "Sources/HiClaude",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "HiClaudeTests", dependencies: ["HiClaude"], path: "Tests/HiClaudeTests"),
    ]
)
