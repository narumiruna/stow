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
    ],
    targets: [
        .target(name: "StowCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "StowCoreTests", dependencies: ["StowCore"]),
    ]
)
