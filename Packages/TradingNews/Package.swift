// swift-tools-version: 6.0
import PackageDescription

// Börsennachrichten mit Merkliste (Entscheidung Tim 02.10.2026, Doc 26, R6).
// RSS-Feeds, Alpaca News und Marketaux; nur Überschrift, Anriss, Quelle, Zeit, Link (Lizenz, R6).
// Ohne Abhängigkeiten; getrennt von TradingCore, damit der Rechenkern ohne Netzwerk bleibt.
let package = Package(
    name: "TradingNews",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingNews", targets: ["TradingNews"])
    ],
    targets: [
        .target(name: "TradingNews"),
        .testTarget(
            name: "TradingNewsTests",
            dependencies: ["TradingNews"]
        )
    ]
)
