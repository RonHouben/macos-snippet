// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "snippingTool",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "snippingToolCore", targets: ["snippingToolCore"]),
        .executable(name: "snippingTool", targets: ["snippingTool"]),
        .executable(name: "snippingToolTDD", targets: ["snippingToolTDD"])
    ],
    targets: [
        .target(
            name: "snippingToolCore",
            path: "Sources/snippingToolCore"
        ),
        .executableTarget(
            name: "snippingTool",
            dependencies: ["snippingToolCore"],
            path: "Sources/snippingTool"
        ),
        .executableTarget(
            name: "snippingToolTDD",
            dependencies: ["snippingToolCore"],
            path: "Sources/snippingToolTDD"
        )
    ]
)
