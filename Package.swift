// swift-tools-version: 6.2
import PackageDescription

// Test the actual helper sources without launching the GUI or changing SMAppService registration.
let package = Package(
    name: "SeekerDaemonTests",
    platforms: [.macOS(.v15)],
    dependencies: [.package(path: "shared")],
    targets: [
        .target(
            name: "SeekerDaemon",
            dependencies: [.product(name: "shared", package: "shared")],
            path: "launchDaemon",
            exclude: ["main.swift"]
        ),
        .testTarget(
            name: "SeekerDaemonTests",
            dependencies: ["SeekerDaemon", .product(name: "shared", package: "shared")],
            path: "launchDaemonTests"
        ),
    ]
)
