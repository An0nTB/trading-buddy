// swift-tools-version: 6.1
import PackageDescription

// Lokale Datenbank des Trading Buddy (SQLite über GRDB, Entscheidung 4 vom 01.10.2026).
// Speichert, was die Importer aus TradingCore liefern, und erkennt doppelte Importe.
let package = Package(
    name: "TradingStore",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "TradingStore", targets: ["TradingStore"])
    ],
    dependencies: [
        .package(path: "../TradingCore"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
        // SHA-256 für den Fingerabdruck einer Datei; auf Apple-Systemen steckt CryptoKit dahinter.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
    ],
    targets: [
        .target(
            name: "TradingStore",
            dependencies: [
                "TradingCore",
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "TradingStoreTests",
            dependencies: ["TradingStore", .product(name: "GRDB", package: "GRDB.swift")]
        )
    ]
)
