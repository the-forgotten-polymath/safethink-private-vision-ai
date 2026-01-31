// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SafeThink",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(name: "SafeThink", targets: ["SafeThink"])
    ],
    dependencies: [
        .package(url: "https://github.com/mattt/llama.swift", from: "2.8235.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.4.1"),
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
        .package(url: "https://github.com/JohnSundell/Splash", from: "0.16.0"),
        .package(url: "https://github.com/jkrukowski/swift-embeddings", from: "0.0.8"),
    ],
    targets: [
        .target(
            name: "SafeThink",
            dependencies: [
                .product(name: "LlamaSwift", package: "llama.swift"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
                .product(name: "Splash", package: "Splash"),
                .product(name: "Embeddings", package: "swift-embeddings"),
            ],
            path: "."
        ),
        .testTarget(
            name: "SafeThinkTests",
            dependencies: ["SafeThink"],
            path: "../SafeThinkTests"
        )
    ]
)
