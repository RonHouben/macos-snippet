// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "snippingTool",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(name: "snippingToolCore", targets: ["snippingToolCore"]),
        .executable(name: "snippingTool", targets: ["snippingTool"]),
        .executable(name: "snippingToolTDD", targets: ["snippingToolTDD"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.31.3"),
    ],
    targets: [
        .target(
            name: "snippingToolCore",
            path: "Sources/snippingToolCore"
        ),
        .executableTarget(
            name: "snippingTool",
            dependencies: [
                "snippingToolCore",
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "MLXVLM", package: "mlx-swift-lm"),
            ],
            path: "Sources/snippingTool"
        ),
        .executableTarget(
            name: "snippingToolTDD",
            dependencies: ["snippingToolCore"],
            path: "Sources/snippingToolTDD"
        )
    ]
)
