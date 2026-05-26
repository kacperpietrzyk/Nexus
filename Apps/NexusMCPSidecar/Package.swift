// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusMCPSidecar",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "nexus-mcp", targets: ["NexusMCPSidecar"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0")
    ],
    targets: [
        .executableTarget(
            name: "NexusMCPSidecar",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(
            name: "NexusMCPSidecarTests",
            dependencies: ["NexusMCPSidecar"]
        ),
    ]
)
