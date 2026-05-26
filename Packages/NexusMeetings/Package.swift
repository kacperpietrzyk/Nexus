// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusMeetings",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NexusMeetings", targets: ["NexusMeetings"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusSync"),
        .package(path: "../NexusAI"),
        .package(path: "../NexusUI"),
        .package(path: "../NexusAgentTools"),
        .package(path: "../NexusSearch"),
        .package(path: "../InboxShell"),
        .package(path: "../TasksFeature"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.4"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "NexusMeetings",
            dependencies: [
                "NexusCore",
                "NexusSync",
                .product(name: "NexusAI", package: "NexusAI"),
                "NexusUI",
                .product(name: "NexusAgentTools", package: "NexusAgentTools"),
                "NexusSearch",
                "InboxShell",
                "TasksFeature",
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ]
        ),
        .testTarget(
            name: "NexusMeetingsTests",
            dependencies: [
                "NexusMeetings",
                "NexusCore",
                "NexusSync",
                .product(name: "NexusAI", package: "NexusAI"),
                .product(name: "NexusAgentTools", package: "NexusAgentTools"),
            ],
            resources: [
                .copy("Import/Fixtures")
            ]
        ),
    ]
)
