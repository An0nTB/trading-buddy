// swift-tools-version: 6.0
import PackageDescription

// „Frag Brad“ (Entscheidung Tim 02.10.2026, Doc 02 Zeile 44, Doc 31): baut die Frage und den Link,
// der Claude Desktop mit vorbefülltem Eingabefeld öffnet. Kein API-Client, kein Schlüssel, kein Netz.
// Ohne Abhängigkeiten, damit die Textregeln unter Linux testbar bleiben.
let package = Package(
    name: "TradingAssistant",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingAssistant", targets: ["TradingAssistant"])
    ],
    targets: [
        .target(name: "TradingAssistant"),
        .testTarget(
            name: "TradingAssistantTests",
            dependencies: ["TradingAssistant"]
        )
    ]
)
