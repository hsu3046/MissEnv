// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MissEnv",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MissEnv", targets: ["MissEnv"]),
        .library(name: "MissEnvCore", targets: ["MissEnvCore"])
    ],
    targets: [
        .target(name: "MissEnvCore"),
        .executableTarget(name: "MissEnv", dependencies: ["MissEnvCore"]),
        .testTarget(name: "MissEnvCoreTests", dependencies: ["MissEnvCore"])
    ]
)
