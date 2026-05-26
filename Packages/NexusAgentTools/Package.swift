// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusAgentTools",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NexusAgentTools", targets: ["NexusAgentTools"]),
        .library(name: "NexusAgentToolsExtras", targets: ["NexusAgentToolsExtras"]),
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../TasksFeature"),
    ],
    targets: [
        .target(
            name: "NexusAgentTools",
            dependencies: ["NexusCore"]
        ),
        .target(
            name: "NexusAgentToolsExtras",
            dependencies: [
                "NexusAgentTools",
                "NexusCore",
                "TasksFeature",
            ]
        ),
        .testTarget(
            name: "NexusAgentToolsTests",
            dependencies: ["NexusAgentTools", "NexusCore"]
        ),
        .testTarget(
            name: "NexusAgentToolsExtrasTests",
            dependencies: ["NexusAgentToolsExtras", "NexusAgentTools", "NexusCore", "TasksFeature"],
            resources: [.process("Fixtures")]
        ),
    ]
)
