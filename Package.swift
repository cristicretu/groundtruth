// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Depth",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "Depth", targets: ["Depth"]),
    ],
    targets: [
        .target(name: "Depth"),
        .testTarget(name: "DepthTests", dependencies: ["Depth"]),
    ]
)
