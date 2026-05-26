// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TasksFeature",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "TasksFeature", targets: ["TasksFeature"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusAI"),
        .package(path: "../NexusAgent"),
        .package(path: "../NexusUI"),
        .package(path: "../InboxShell"),
        .package(path: "../CommandPaletteShell"),
    ],
    targets: [
        .target(
            name: "TasksFeature",
            dependencies: [
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusAI", package: "NexusAI"),
                .product(name: "NexusAgent", package: "NexusAgent"),
                .product(name: "NexusUI", package: "NexusUI"),
                .product(name: "InboxShell", package: "InboxShell"),
                .product(name: "CommandPaletteShell", package: "CommandPaletteShell"),
            ]
        ),
        .testTarget(
            name: "TasksFeatureTests",
            dependencies: [
                "TasksFeature",
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusAI", package: "NexusAI"),
                .product(name: "NexusAgent", package: "NexusAgent"),
                .product(name: "NexusUI", package: "NexusUI"),
                .product(name: "InboxShell", package: "InboxShell"),
                .product(name: "CommandPaletteShell", package: "CommandPaletteShell"),
            ]
        ),
    ]
)
