// swift-tools-version: 5.9
import PackageDescription

// Vendored from github.com/li3zhen1/Grape (MIT © Zhen Li).
// Only the self-contained ForceSimulation module is included.
// Local patch: public `positions` accessor on Kinetics (Kinetics.swift).
let package = Package(
    name: "ForceSimulationVendor",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10),
    ],
    products: [
        .library(name: "ForceSimulation", targets: ["ForceSimulation"])
    ],
    targets: [
        .target(
            name: "ForceSimulation",
            path: "Sources/ForceSimulation",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)
