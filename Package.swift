// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "perch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerchCore", targets: ["PerchCore"]),
        .executable(name: "perch", targets: ["perch"]),
        .executable(name: "perchd", targets: ["perchd"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Models, wire protocol, paths. Shared by the CLI, the daemon and the notch app.
        .target(name: "PerchCore"),
        // `perch` — the CLI. The only contract agents and humans use.
        .executableTarget(
            name: "perch",
            dependencies: [
                "PerchCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // `perchd` — the daemon. Owns SQLite, the Unix socket and the localhost HTTP port.
        .executableTarget(name: "perchd", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ]
)
