// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StowDesktopBridge",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "StowDesktopBridge", type: .static, targets: ["StowDesktopBridge"]),
        .executable(name: "StowBridgeFixture", targets: ["StowBridgeFixture"]),
    ],
    dependencies: [.package(path: "../../../Packages/StowCore")],
    targets: [
        .target(name: "StowDesktopBridge", dependencies: ["StowCore"]),
        // Verification executable only. It is not part of the bridge static library.
        .target(name: "StowBridgeFixtureSupport", dependencies: ["StowDesktopBridge", "StowCore"], path: "Tests/StowBridgeFixtureSupport"),
        .executableTarget(name: "StowBridgeFixture", dependencies: ["StowBridgeFixtureSupport"], path: "Tests/StowBridgeFixture"),
        .testTarget(name: "StowDesktopBridgeTests", dependencies: ["StowDesktopBridge", "StowCore", "StowBridgeFixtureSupport"]),
    ]
)
