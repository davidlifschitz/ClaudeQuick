// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeQuick",
    platforms: [
        .macOS(.v12)
    ],
    dependencies: [
        .package(url: "https://github.com/ccgus/fmdb.git", from: "2.7.5")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeQuick",
            dependencies: [
                .product(name: "FMDB", package: "fmdb")
            ],
            path: "ClaudeQuick",
            sources: [
                "App",
                "Models",
                "Services",
                "Views"
            ],
            resources: []
        ),
        .testTarget(
            name: "ClaudeQuickTests",
            dependencies: ["ClaudeQuick"],
            path: "ClaudeQuickTests"
        )
    ]
)
