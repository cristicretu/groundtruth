// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Depth",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Depth", targets: ["Depth"]),
        .library(name: "Scene", targets: ["Scene"]),
    ],
    targets: [
        .target(name: "Depth"),
        .target(name: "Scene"),
        .testTarget(name: "DepthTests", dependencies: ["Depth"]),
        .testTarget(name: "SceneTests", dependencies: ["Scene"]),
    ]
)
