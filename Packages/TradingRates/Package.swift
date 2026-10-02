// swift-tools-version: 6.0
import PackageDescription

// EZB-Referenzkurse für die Steuer-Orientierung (Doc 02 Entscheidung 47, Tim 02.10.2026):
// lädt die Euro-Referenzkurse der EZB, legt sie als Datei ab und liefert `Referenzkurse` aus TradingCore.
// Getrennt vom Kern, damit TradingCore ohne Netzwerk bleibt (wie TradingQuotes).
let package = Package(
    name: "TradingRates",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingRates", targets: ["TradingRates"])
    ],
    dependencies: [
        .package(path: "../TradingCore")
    ],
    targets: [
        .target(
            name: "TradingRates",
            dependencies: ["TradingCore"]
        ),
        .testTarget(
            name: "TradingRatesTests",
            dependencies: ["TradingRates", "TradingCore"],
            resources: [.copy("Fixtures")]
        )
    ]
)
