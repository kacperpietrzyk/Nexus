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
        // Pin exact 0.31.4: 0.31.5 adds an iOS-incompatible Encuda/Process target
        // (no #if os(macOS) guard → NexusiOS build fails) + a CudaBuild build-tool
        // plugin headless xcodebuild rejects. Revisit when upstream guards Encuda
        // for non-macOS. mlx-swift-lm 3.31.4 allows >=0.31.4 <0.32.0.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.31.4"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.31.4"),
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
