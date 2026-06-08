// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PeopleFeature",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "PeopleFeature", targets: ["PeopleFeature"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusUI"),
    ],
    targets: [
        .target(
            name: "PeopleFeature",
            dependencies: [
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
        .testTarget(
            name: "PeopleFeatureTests",
            dependencies: [
                "PeopleFeature",
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
    ]
)
