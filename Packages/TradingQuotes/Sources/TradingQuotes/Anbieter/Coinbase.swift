import Foundation

/// Coinbase Advanced Trade WebSocket, Kanal „ticker“, ohne Anmeldung (R1 Abschnitt 3).
/// Format laut docs.cdp.coinbase.com (Advanced Trade, WebSocket Channels und Ticker), gelesen 02.10.2026:
/// Adresse wss://advanced-trade-ws.coinbase.com, „A JWT is not required“ für Marktdaten;
/// Abo `{"type":"subscribe","channel":"ticker","product_ids":["BTC-EUR"]}`;
/// Antwort mit `channel`, `timestamp` (RFC 3339), `events[].tickers[]` mit `product_id`, `price`,
/// `best_bid`, `best_ask` als Text. Der Kanal „heartbeats“ hält ruhige Verbindungen offen.
struct CoinbaseLeser: Nachrichtenleser {
    let symbole: [String]

    static let adresse = URL(string: "wss://advanced-trade-ws.coinbase.com")!

    private struct Abo: Encodable {
        let type = "subscribe"
        let channel: String
        let product_ids: [String]
    }

    private struct Kopf: Decodable {
        let channel: String?
        let type: String?
        let message: String?
    }

    private struct Nachricht: Decodable {
        struct Ereignis: Decodable {
            let tickers: [Eintrag]?
        }
        let timestamp: String?
        let events: [Ereignis]
    }

    private struct Eintrag: Decodable {
        let product_id: String
        let price: Zahl?
        let best_bid: Zahl?
        let best_ask: Zahl?
    }

    func start() -> [String] {
        [jsonText(Abo(channel: "ticker", product_ids: symbole)),
         jsonText(Abo(channel: "heartbeats", product_ids: symbole))]
    }

    mutating func lies(_ text: String, empfangen: Date) -> Lesung {
        let daten = Data(text.utf8)
        guard let kopf = try? JSONDecoder().decode(Kopf.self, from: daten) else { return Lesung() }
        if kopf.type == "error" {
            // Coinbase schließt nach einem Fehler die Verbindung; neu verbinden hilft bei falschen Symbolen nicht.
            return Lesung(abbruch: "Coinbase: \(kopf.message ?? "Fehler")")
        }
        guard kopf.channel == "ticker",
              let nachricht = try? JSONDecoder().decode(Nachricht.self, from: daten)
        else { return Lesung() }
        let zeit = nachricht.timestamp.flatMap(Zeitstempel.lies) ?? empfangen
        let eintraege = nachricht.events.flatMap { $0.tickers ?? [] }
        let kurse = eintraege.map { e in
            Kurs(symbol: e.product_id, letzter: e.price?.wert, geld: e.best_bid?.wert, brief: e.best_ask?.wert,
                 zeit: zeit, quelle: "coinbase")
        }
        return Lesung(kurse: kurse)
    }
}

extension Kursquellen {
    /// Krypto in Echtzeit über Coinbase. Symbole wie "BTC-EUR".
    public static func coinbase(verbinde: @escaping WebSocketFabrik = URLSessionVerbindung.fabrik) -> any Kursquelle {
        WebSocketKursquelle(
            id: "coinbase", name: "Coinbase", verzoegerung: .echtzeit, hoechstzahlSymbole: nil,
            adresse: { _ in CoinbaseLeser.adresse },
            macheLeser: { CoinbaseLeser(symbole: $0) },
            verbinde: verbinde, warte: Kursquellen.schlafe, jetzt: { Date() })
    }
}
