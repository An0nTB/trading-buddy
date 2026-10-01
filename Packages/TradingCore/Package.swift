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
    dependencies: [
        // Entpackt Excel-Dateien (XLSX ist ein ZIP-Archiv). MIT-Lizenz; Entscheidung Tim 01.10.2026.
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", .upToNextMinor(from: "0.9.20"))
    ],
    targets: [
        .target(
            name: "TradingCore",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
        ),
        .testTarget(
            name: "TradingCoreTests",
            dependencies: ["TradingCore"],
            exclude: ["Fixtures"]
        )
    ]
)
