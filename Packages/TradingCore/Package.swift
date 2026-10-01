// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TradingCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingCore", targets: ["TradingCore"])
    ],
    targets: [
        .target(name: "TradingCore"),
        .testTarget(name: "TradingCoreTests", dependencies: ["TradingCore"])
    ]
)
