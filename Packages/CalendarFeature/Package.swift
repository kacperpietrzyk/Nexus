// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CalendarFeature",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "CalendarFeature", targets: ["CalendarFeature"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusUI"),
    ],
    targets: [
        .target(
            name: "CalendarFeature",
            dependencies: [
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
        .testTarget(
            name: "CalendarFeatureTests",
            dependencies: [
                "CalendarFeature",
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusUI", package: "NexusUI"),
            ]
        ),
    ]
)
