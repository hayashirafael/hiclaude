// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Ohayo",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Ohayo", path: "Sources/Ohayo",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "OhayoTests",
            dependencies: ["Ohayo"],
            path: "Tests/OhayoTests"
        ),
    ]
)
