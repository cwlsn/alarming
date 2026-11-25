// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AlarmingCore",
    platforms: [.iOS("26.1"), .macOS(.v15)],
    products: [.library(name: "AlarmingCore", targets: ["AlarmingCore"])],
    targets: [
        .target(name: "AlarmingCore"),
        .testTarget(name: "AlarmingCoreTests", dependencies: ["AlarmingCore"]),
    ]
)
