// swift-tools-version: 6.0
import PackageDescription

// Börsenuhr des Trading Buddy: Handelszeiten und Feiertage je Börse als JSON-Datei
// (R1 Abschnitt 6), daraus „ist offen?“ und „nächste Öffnung oder Schließung“.
// Ohne Oberfläche und ohne Abhängigkeiten; die App hängt die Anzeige später ein.
let package = Package(
    name: "TradingClock",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingClock", targets: ["TradingClock"])
    ],
    targets: [
        .target(
            name: "TradingClock",
            resources: [.copy("Boersen")]
        ),
        .testTarget(
            name: "TradingClockTests",
            dependencies: ["TradingClock"]
        )
    ]
)
