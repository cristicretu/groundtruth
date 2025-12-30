// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PathfinderDebug",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "PathfinderDebug",
            path: ".",
            sources: ["DebugApp.swift"]
        )
    ]
)
