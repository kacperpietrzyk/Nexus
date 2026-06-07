// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotesFeature",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NotesFeature", targets: ["NotesFeature"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusUI"),
    ],
    targets: [
        .target(
            name: "NotesFeature",
            dependencies: [
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
        .testTarget(
            name: "NotesFeatureTests",
            dependencies: [
                "NotesFeature",
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
    ]
)
