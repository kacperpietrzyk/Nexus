// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusSync",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "NexusSync", targets: ["NexusSync"])
    ],
    dependencies: [
        .package(path: "../NexusCore")
    ],
    targets: [
        .target(name: "NexusSync", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusSyncTests", dependencies: ["NexusSync", "NexusCore"]),
    ]
)
