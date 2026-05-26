// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NexusAI",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "NexusAI", targets: ["NexusAI"])
    ],
    dependencies: [
        .package(path: "../NexusCore"),
        .package(path: "../NexusSync"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.0.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", exact: "1.3.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.31.3"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.3"),
    ],
    targets: [
        .target(
            name: "NexusAI",
            dependencies: [
                "NexusCore",
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXEmbedders", package: "mlx-swift-lm"),
            ],
            resources: [.process("ModelCatalog/Resources")]),
        .testTarget(
            name: "NexusAITests",
            dependencies: [
                "NexusAI",
                .product(name: "NexusCore", package: "NexusCore"),
                .product(name: "NexusSync", package: "NexusSync"),
            ]),
    ]
)
