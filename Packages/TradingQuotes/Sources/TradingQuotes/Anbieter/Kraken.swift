import Foundation

/// Kraken WebSocket v2, Kanal „ticker“, ohne Schlüssel (R1 Abschnitt 3).
/// Format laut docs.kraken.com/api/docs/websocket-v2/ticker, gelesen 02.10.2026:
/// Abo `{"method":"subscribe","params":{"channel":"ticker","symbol":["BTC/EUR"]}}`,
/// Antwort `{"channel":"ticker","type":"snapshot"|"update","data":[{"symbol","bid","ask","last","timestamp",…}]}`,
/// Zahlen als JSON-Zahlen. Symbole mit Schrägstrich, Bitcoin heißt in v2 „BTC“.
struct KrakenLeser: Nachrichtenleser {
    let symbole: [String]

    static let adresse = URL(string: "wss://ws.kraken.com/v2")!

    private struct Abo: Encodable {
        struct Parameter: Encodable {
            let channel = "ticker"
            let symbol: [String]
        }
        let method = "subscribe"
        let params: Parameter
    }

    private struct Kopf: Decodable {
        let channel: String?
        let type: String?
    }

    private struct Nachricht: Decodable {
        let data: [Eintrag]
    }

    private struct Eintrag: Decodable {
        let symbol: String
        let bid: Zahl?
        let ask: Zahl?
        let last: Zahl?
        let timestamp: String?
    }

    func start() -> [String] {
        [jsonText(Abo(params: .init(symbol: symbole)))]
    }

    mutating func lies(_ text: String, empfangen: Date) -> Lesung {
        let daten = Data(text.utf8)
        // Erst nur den Kopf lesen: Kanäle wie „status“ und „heartbeat“ haben andere Felder.
        guard let kopf = try? JSONDecoder().decode(Kopf.self, from: daten),
              kopf.channel == "ticker", kopf.type == "snapshot" || kopf.type == "update",
              let nachricht = try? JSONDecoder().decode(Nachricht.self, from: daten)
        else { return Lesung() }
        let kurse = nachricht.data.map { e in
            Kurs(symbol: e.symbol, letzter: e.last?.wert, geld: e.bid?.wert, brief: e.ask?.wert,
                 zeit: e.timestamp.flatMap(Zeitstempel.lies) ?? empfangen, quelle: "kraken")
        }
        return Lesung(kurse: kurse)
    }
}

extension Kursquellen {
    /// Krypto in Echtzeit über Kraken. Symbole wie "BTC/EUR".
    public static func kraken(verbinde: @escaping WebSocketFabrik = URLSessionVerbindung.fabrik) -> any Kursquelle {
        WebSocketKursquelle(
            id: "kraken", name: "Kraken", verzoegerung: .echtzeit, hoechstzahlSymbole: nil,
            adresse: { _ in KrakenLeser.adresse },
            macheLeser: { KrakenLeser(symbole: $0) },
            verbinde: verbinde, warte: Kursquellen.schlafe, jetzt: { Date() })
    }
}
