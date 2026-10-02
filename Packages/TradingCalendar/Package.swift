// swift-tools-version: 6.0
import PackageDescription

// Terminkalender des Trading Buddy: Zinsentscheide und wichtige US-Daten als JSON je Jahr
// (R1 Abschnitt 5: keine frei nutzbare Kalender-API, daher Datei, jährlich nachgezogen).
// Ohne Abhängigkeiten; die App verbindet die Termine mit der Haltezeit eines Trades (Doc 18 F9).
let package = Package(
    name: "TradingCalendar",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingCalendar", targets: ["TradingCalendar"])
    ],
    targets: [
        .target(
            name: "TradingCalendar",
            resources: [.copy("Termine")]
        ),
        .testTarget(
            name: "TradingCalendarTests",
            dependencies: ["TradingCalendar"]
        )
    ]
)
