// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusCore",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "NexusCore", targets: ["NexusCore"])
    ],
    targets: [
        .target(name: "NexusCore"),
        .testTarget(
            name: "NexusCoreTests",
            dependencies: ["NexusCore"],
            resources: [.process("Vision/Fixtures")]
        ),
    ]
)
