import ConnectorKern
import Foundation
import MCP

enum Umgebung {
    /// Kommt aus manifest.json (scripts/connector_bauen.sh), z. B. ABCDE12345.journal
    static let gruppe = ProcessInfo.processInfo.environment["TB_APP_GROUP"]
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let leeresSchema: Value = .object([
        "type": .string("object"),
        "properties": .object([:])
    ])
}

let server = Server(
    name: "trading-buddy",
    version: "0.0.1",
    capabilities: .init(tools: .init(listChanged: false))
)

await server.withMethodHandler(ListTools.self) { _ in
    .init(tools: [
        Tool(
            name: "hole_kennzahlen",
            description: "Liefert Kennzahlen aus dem Trading Buddy. Im Experiment feste Beispielwerte.",
            inputSchema: Umgebung.leeresSchema,
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        ),
        Tool(
            name: "pruefe_datenweg",
            description: "Prüft, ob der Server die Testdatei der Trading-Buddy-App lesen kann.",
            inputSchema: Umgebung.leeresSchema,
            annotations: .init(readOnlyHint: true, openWorldHint: false)
        )
    ])
}

await server.withMethodHandler(CallTool.self) { params in
    switch params.name {
    case "hole_kennzahlen":
        return .init(content: [.text(text: Beispielkennzahlen.text, annotations: nil, _meta: nil)])
    case "pruefe_datenweg":
        let ergebnis = Datenweg.pruefe(gruppe: Umgebung.gruppe, home: Umgebung.home)
        var istFehler = true
        if case .gelesen = ergebnis { istFehler = false }
        return .init(
            content: [.text(text: Datenweg.text(ergebnis), annotations: nil, _meta: nil)],
            isError: istFehler
        )
    default:
        return .init(content: [.text(text: "Unbekanntes Werkzeug", annotations: nil, _meta: nil)], isError: true)
    }
}

try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
