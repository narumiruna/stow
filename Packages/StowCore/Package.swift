// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "StowCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "StowCore", targets: ["StowCore"]),
        .executable(name: "stow", targets: ["StowCLI"]),
    ],
    targets: [
        .target(name: "StowCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "StowCLI", dependencies: ["StowCore"]),
        .testTarget(name: "StowCoreTests", dependencies: ["StowCore"]),
        .testTarget(name: "StowCLITests", dependencies: ["StowCLI", "StowCore"]),
    ]
)
