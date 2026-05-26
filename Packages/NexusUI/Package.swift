// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusUI",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
        .watchOS(.v26),
    ],
    products: [
        .library(name: "NexusUI", targets: ["NexusUI"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusAI"),
        .package(path: "../NexusAgentTools"),
    ],
    targets: [
        .target(
            name: "NexusUI",
            dependencies: [
                "NexusCore",
                .product(name: "NexusAI", package: "NexusAI", condition: .when(platforms: [.macOS, .iOS])),
                .product(
                    name: "NexusAgentTools",
                    package: "NexusAgentTools",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
            ],
            resources: [
                .process("Resources/Fonts"),
                .process("Resources/Wallpaper"),
            ]
        ),
        .testTarget(
            name: "NexusUITests",
            dependencies: [
                "NexusUI",
                .product(name: "NexusAI", package: "NexusAI", condition: .when(platforms: [.macOS, .iOS])),
                .product(
                    name: "NexusAgentTools",
                    package: "NexusAgentTools",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
            ]),
    ]
)
