// swift-tools-version: 6.0
import PackageDescription

// Kurse für offene Trades (Entscheidung 1, Option 1 gratis; R1 Abschnitt 7).
// Ein Protokoll `Kursquelle`, ein Anbieter je Datei.
// Getrennt von TradingCore, damit der Rechenkern ohne Netzwerk bleibt. Hängt seit Paket B2 (Doc 39) von
// TradingCore ab, weil Minutenkerzen als `Zeitkerze` des Kerns geliefert werden (wie TradingRates).
let package = Package(
    name: "TradingQuotes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingQuotes", targets: ["TradingQuotes"])
    ],
    dependencies: [
        .package(path: "../TradingCore")
    ],
    targets: [
        .target(
            name: "TradingQuotes",
            dependencies: [.product(name: "TradingCore", package: "TradingCore")]
        ),
        .testTarget(
            name: "TradingQuotesTests",
            dependencies: ["TradingQuotes", .product(name: "TradingCore", package: "TradingCore")]
        )
    ]
)
