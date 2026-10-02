import Foundation

/// Binance Spot, Strom „<symbol>@ticker“ über den reinen Marktdaten-Zugang, ohne Schlüssel (R1: Ersatzquelle).
/// Format laut github.com/binance/binance-spot-api-docs, web-socket-streams.md, gelesen 02.10.2026:
/// „wss://data-stream.binance.vision can be subscribed to receive only market data messages“;
/// kombinierte Ströme über /stream?streams=a/b, Antwort `{"stream":…,"data":{…}}`;
/// Ticker-Felder `s` Symbol, `c` letzter, `b` Geld, `a` Brief (Text), `E` Ereigniszeit in ms.
/// Eine Verbindung gilt höchstens 24 Stunden; die Quelle verbindet sich dann selbst neu.
struct BinanceLeser: Nachrichtenleser {
    static func adresse(_ symbole: [String]) -> URL {
        let stroeme = symbole.map { $0.lowercased() + "@ticker" }.joined(separator: "/")
        return URL(string: "wss://data-stream.binance.vision/stream?streams=" + stroeme)!
    }

    private struct Nachricht: Decodable {
        let data: Eintrag
    }

    private struct Eintrag: Decodable {
        let e: String
        let E: Int64?
        let s: String
        let c: Zahl?
        let b: Zahl?
        let a: Zahl?
    }

    /// Das Abo steckt in der Adresse.
    func start() -> [String] { [] }

    mutating func lies(_ text: String, empfangen: Date) -> Lesung {
        guard let nachricht = try? JSONDecoder().decode(Nachricht.self, from: Data(text.utf8)),
              nachricht.data.e == "24hrTicker"
        else { return Lesung() }
        let e = nachricht.data
        let zeit = e.E.map(Zeitstempel.ausMillisekunden) ?? empfangen
        return Lesung(kurse: [Kurs(symbol: e.s, letzter: e.c?.wert, geld: e.b?.wert, brief: e.a?.wert,
                                   zeit: zeit, quelle: "binance")])
    }
}

extension Kursquellen {
    /// Krypto in Echtzeit über Binance. Symbole wie "BTCEUR" (ohne Trennzeichen).
    /// Laut Doku höchstens 1.024 Ströme je Verbindung.
    public static func binance(verbinde: @escaping WebSocketFabrik = URLSessionVerbindung.fabrik) -> any Kursquelle {
        WebSocketKursquelle(
            id: "binance", name: "Binance", verzoegerung: .echtzeit, hoechstzahlSymbole: 1024,
            adresse: { BinanceLeser.adresse($0) },
            macheLeser: { _ in BinanceLeser() },
            verbinde: verbinde, warte: Kursquellen.schlafe, jetzt: { Date() })
    }
}
