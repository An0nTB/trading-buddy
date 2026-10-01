// swift-tools-version: 6.1
import PackageDescription

// Lokaler MCP-Server für Claude Desktop (wird als .mcpb verpackt).
// ConnectorKern enthält die reine Logik und ist ohne MCP testbar.
// tb-export baut die Exportdatei aus MT4-Auszügen, damit der Connector ohne App testbar ist.
let package = Package(
    name: "TradingConnector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "trading-buddy-mcp", targets: ["trading-buddy-mcp"]),
        .executable(name: "tb-export", targets: ["tb-export"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(path: "../TradingCore")
    ],
    targets: [
        .target(
            name: "ConnectorKern",
            dependencies: [.product(name: "TradingCore", package: "TradingCore")]
        ),
        .executableTarget(
            name: "trading-buddy-mcp",
            dependencies: [
                "ConnectorKern",
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "TradingCore", package: "TradingCore")
            ]
        ),
        .executableTarget(
            name: "tb-export",
            dependencies: [.product(name: "TradingCore", package: "TradingCore")]
        ),
        .testTarget(
            name: "ConnectorKernTests",
            dependencies: ["ConnectorKern", .product(name: "TradingCore", package: "TradingCore")]
        )
    ]
)
