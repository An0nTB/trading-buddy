// swift-tools-version: 6.1
import PackageDescription

// Lokaler MCP-Server für Claude Desktop (wird als .mcpb verpackt).
// ConnectorKern enthält die reine Logik und ist ohne MCP testbar.
let package = Package(
    name: "TradingConnector",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "trading-buddy-mcp", targets: ["trading-buddy-mcp"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .target(name: "ConnectorKern"),
        .executableTarget(
            name: "trading-buddy-mcp",
            dependencies: [
                "ConnectorKern",
                .product(name: "MCP", package: "swift-sdk")
            ]
        ),
        .testTarget(name: "ConnectorKernTests", dependencies: ["ConnectorKern"])
    ]
)
