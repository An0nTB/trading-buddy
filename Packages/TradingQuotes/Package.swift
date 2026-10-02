// swift-tools-version: 6.0
import PackageDescription

// Kurse für offene Trades (Entscheidung 1, Option 1 gratis; R1 Abschnitt 7).
// Ein Protokoll `Kursquelle`, ein Anbieter je Datei; ohne Abhängigkeiten.
// Getrennt von TradingCore, damit der Rechenkern ohne Netzwerk bleibt.
let package = Package(
    name: "TradingQuotes",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingQuotes", targets: ["TradingQuotes"])
    ],
    targets: [
        .target(name: "TradingQuotes"),
        .testTarget(
            name: "TradingQuotesTests",
            dependencies: ["TradingQuotes"]
        )
    ]
)
