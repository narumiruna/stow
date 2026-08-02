// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LocalSearchSpike",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/StowCore")],
    targets: [
        .executableTarget(name: "LocalSearchBenchmark", dependencies: ["StowCore"], linkerSettings: [.linkedFramework("CoreSpotlight")])
    ]
)
