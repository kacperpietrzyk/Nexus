// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "InboxShell",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "InboxShell", targets: ["InboxShell"])
    ],
    dependencies: [
        .package(path: "../NexusUI"),
        .package(path: "../CommandPaletteShell"),
    ],
    targets: [
        .target(
            name: "InboxShell",
            dependencies: [
                .product(name: "NexusUI", package: "NexusUI"),
                .product(name: "CommandPaletteShell", package: "CommandPaletteShell"),
            ]
        ),
        .testTarget(
            name: "InboxShellTests",
            dependencies: ["InboxShell"]
        ),
    ]
)
