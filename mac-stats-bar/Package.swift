// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacStatsBar",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacStatsBar", targets: ["MacStatsBar"])],
    targets: [
        .target(name: "StatsCore"),
        .executableTarget(name: "MacStatsBar", dependencies: ["StatsCore"]),
        .executableTarget(name: "StatsCoreChecks", dependencies: ["StatsCore"], path: "Tests/StatsCoreTests")
    ]
)
