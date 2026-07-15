// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "GitHubReady",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GitHubReady", targets: ["GitHubReady"])
    ],
    targets: [
        .executableTarget(
            name: "GitHubReady",
            path: "Sources/GitHubReady",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "GitHubReadyTests",
            dependencies: ["GitHubReady"],
            path: "Tests/GitHubReadyTests"
        )
    ]
)
