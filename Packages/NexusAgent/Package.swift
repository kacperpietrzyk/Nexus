// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusAgent",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NexusAgent", targets: ["NexusAgent"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusSync"),
        .package(path: "../NexusAI"),
        .package(path: "../NexusSearch"),
        .package(path: "../NexusUI"),
        .package(path: "../NexusAgentTools"),
        .package(path: "../InboxShell"),
    ],
    targets: [
        .target(
            name: "CSqliteVec",
            publicHeadersPath: "include",
            cSettings: [
                .define("SQLITE_VEC_STATIC"),
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "NexusAgent",
            dependencies: [
                "CSqliteVec",
                "NexusCore",
                .product(name: "NexusSync", package: "NexusSync"),
                .product(name: "NexusAI", package: "NexusAI"),
                .product(name: "NexusSearch", package: "NexusSearch"),
                .product(name: "NexusUI", package: "NexusUI"),
                .product(name: "NexusAgentTools", package: "NexusAgentTools"),
                .product(name: "InboxShell", package: "InboxShell"),
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "NexusAgentTests",
            dependencies: [
                "CSqliteVec",
                "NexusAgent",
                .product(name: "NexusSync", package: "NexusSync"),
                .product(name: "InboxShell", package: "InboxShell"),
            ]
        ),
    ]
)
