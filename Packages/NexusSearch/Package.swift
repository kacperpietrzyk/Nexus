// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusSearch",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NexusSearch", targets: ["NexusSearch"])
    ],
    dependencies: [
        .package(path: "../NexusCore")
    ],
    targets: [
        .target(name: "NexusSearch", dependencies: ["NexusCore"]),
        .testTarget(name: "NexusSearchTests", dependencies: ["NexusSearch"]),
    ]
)
