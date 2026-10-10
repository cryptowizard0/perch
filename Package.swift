// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "perch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerchCore", targets: ["PerchCore"]),
        .library(name: "PerchClient", targets: ["PerchClient"]),
        .executable(name: "perch", targets: ["perch"]),
        .executable(name: "perchd", targets: ["perchd"]),
        .executable(name: "PerchApp", targets: ["PerchApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        // Models, wire protocol, paths, pure parsing/rendering. Shared by every client. No I/O.
        .target(name: "PerchCore"),
        // Socket client for perchd. Used by the CLI and the notch app.
        .target(name: "PerchClient", dependencies: ["PerchCore"]),
        // Declarations for the system libsqlite3 (see Sources/CSQLite/include/CSQLite.h for why).
        .target(name: "CSQLite", linkerSettings: [.linkedLibrary("sqlite3")]),
        // The daemon as a library: SQLite store, request handling, socket + HTTP servers, file mirror.
        .target(name: "PerchDaemon", dependencies: ["CSQLite", "PerchCore", "PerchClient"]),
        // Installing Perch: agent hook files, perchd's launchd agent, the fixed install location, agents.json.
        // Does I/O, so it is not in PerchCore. Used by the CLI and perchd (the notch app next, #25).
        .target(name: "PerchSetup", dependencies: ["PerchCore", "PerchClient"]),
        // `perch` — the CLI. The only contract agents and humans use.
        .executableTarget(
            name: "perch",
            dependencies: [
                "PerchCore",
                "PerchClient",
                "PerchSetup",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // `perchd` — the daemon executable. Owns SQLite, the Unix socket and the localhost HTTP port.
        .executableTarget(
            name: "perchd",
            dependencies: [
                "PerchCore",
                "PerchDaemon",
                "PerchSetup",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        // The notch app (AppKit + SwiftUI). Bundled into Perch.app by scripts/bundle-app.sh; no Xcode needed.
        .executableTarget(name: "PerchApp", dependencies: ["PerchCore", "PerchClient", "PerchAppCore"]),
        // The notch app's testable logic: geometry, queue state, reminders, the perchd connection. No AppKit.
        .target(name: "PerchAppCore", dependencies: ["PerchCore", "PerchClient"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchDaemonTests", dependencies: ["PerchCore", "PerchClient", "PerchDaemon", "PerchAppCore"]),
        .testTarget(name: "PerchAppCoreTests", dependencies: ["PerchCore", "PerchAppCore"]),
        .testTarget(name: "PerchSetupTests", dependencies: ["PerchCore", "PerchSetup"]),
    ]
)
