// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CommandPaletteShell",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "CommandPaletteShell", targets: ["CommandPaletteShell"])
    ],
    dependencies: [
        .package(path: "../NexusUI")
    ],
    targets: [
        .target(
            name: "CommandPaletteShell",
            dependencies: [
                .product(name: "NexusUI", package: "NexusUI")
            ]
        ),
        .testTarget(
            name: "CommandPaletteShellTests",
            dependencies: ["CommandPaletteShell"]
        ),
    ]
)
