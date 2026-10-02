import Foundation

/// Schlüssel für Alpaca. Kommt zur Laufzeit aus dem Schlüsselbund der App, nie aus Dateien.
public struct AlpacaSchluessel: Sendable, Equatable, CustomStringConvertible {
    public var schluesselID: String
    public var geheimnis: String

    public init(schluesselID: String, geheimnis: String) {
        self.schluesselID = schluesselID
        self.geheimnis = geheimnis
    }

    /// Nie den Schlüssel in Protokolle schreiben.
    public var description: String { "AlpacaSchluessel(***)" }
}

/// Liefert den Schlüssel; die App liest ihn aus dem Schlüsselbund. `nil`, wenn keiner eingetragen ist.
public protocol AlpacaSchluesselquelle: Sendable {
    func alpacaSchluessel() async throws -> AlpacaSchluessel?
}

/// Alpaca, US-Aktien in Echtzeit über den Teilmarkt IEX (R1: gratis, 30 Symbole laut alpaca.markets/data, 02.10.2026).
/// Format laut docs.alpaca.markets (Real-time Stock Data, Streaming Market Data), gelesen 02.10.2026:
/// Adresse wss://stream.data.alpaca.markets/v2/iex; Ablauf `[{"T":"success","msg":"connected"}]`,
/// dann `{"action":"auth","key":…,"secret":…}`, Antwort `[{"T":"success","msg":"authenticated"}]`,
/// dann `{"action":"subscribe","trades":[…],"quotes":[…]}`. Abschluss `T":"t"` mit `p`, Kursblatt `"T":"q"`
/// mit `bp`, `ap`, Zeit `t` (RFC 3339). Fehler `"T":"error"` mit `code` und `msg`.
struct AlpacaLeser: Nachrichtenleser {
    let symbole: [String]
    let schluessel: AlpacaSchluessel
    /// Letzter Stand je Symbol: Abschlüsse und Kursblatt kommen getrennt und werden zusammengeführt.
    private var stand: [String: Kurs] = [:]

    init(symbole: [String], schluessel: AlpacaSchluessel) {
        self.symbole = symbole
        self.schluessel = schluessel
    }

    static let adresse = URL(string: "wss://stream.data.alpaca.markets/v2/iex")!

    private struct Anmeldung: Encodable {
        let action = "auth"
        let key: String
        let secret: String
    }

    private struct Abo: Encodable {
        let action = "subscribe"
        let trades: [String]
        let quotes: [String]
    }

    private struct Eintrag: Decodable {
        let T: String
        let S: String?
        let p: Zahl?
        let bp: Zahl?
        let ap: Zahl?
        let t: String?
        let msg: String?
        let code: Int?
    }

    /// Erst nach „connected“ anmelden.
    func start() -> [String] { [] }

    mutating func lies(_ text: String, empfangen: Date) -> Lesung {
        guard let eintraege = try? JSONDecoder().decode([Eintrag].self, from: Data(text.utf8)) else { return Lesung() }
        var lesung = Lesung()
        for e in eintraege {
            switch e.T {
            case "success" where e.msg == "connected":
                lesung.senden.append(jsonText(Anmeldung(key: schluessel.schluesselID, secret: schluessel.geheimnis)))
            case "success" where e.msg == "authenticated":
                lesung.senden.append(jsonText(Abo(trades: symbole, quotes: symbole)))
            case "error":
                // 407 (zu langsam) und 500 (Serverfehler) enden mit Trennung und neuem Versuch, der Rest ist endgültig.
                if let code = e.code, code != 407, code < 500 {
                    lesung.abbruch = "Alpaca \(code): \(e.msg ?? "Fehler")"
                }
            case "t", "q":
                if let kurs = uebernimm(e, empfangen: empfangen) { lesung.kurse.append(kurs) }
            default:
                break
            }
        }
        return lesung
    }

    private mutating func uebernimm(_ e: Eintrag, empfangen: Date) -> Kurs? {
        guard let symbol = e.S else { return nil }
        let zeit = e.t.flatMap(Zeitstempel.lies) ?? empfangen
        var kurs = stand[symbol] ?? Kurs(symbol: symbol, zeit: zeit, quelle: "alpaca")
        kurs.zeit = zeit
        if e.T == "t" {
            kurs.letzter = e.p?.wert
        } else {
            kurs.geld = e.bp?.wert
            kurs.brief = e.ap?.wert
        }
        stand[symbol] = kurs
        return kurs.preis == nil ? nil : kurs
    }
}

extension Kursquellen {
    /// US-Aktien in Echtzeit (nur Handelsplatz IEX) über Alpaca. Symbole wie "AAPL".
    /// Ohne Schlüssel endet die Quelle mit Status `.beendet("Schlüssel fehlt")`.
    public static func alpaca(schluessel: any AlpacaSchluesselquelle,
                              verbinde: @escaping WebSocketFabrik = URLSessionVerbindung.fabrik) -> any Kursquelle {
        WebSocketKursquelle(
            id: "alpaca", name: "Alpaca (IEX)", verzoegerung: .echtzeit, hoechstzahlSymbole: 30,
            adresse: { _ in AlpacaLeser.adresse },
            macheLeser: { symbole in
                guard let s = try await schluessel.alpacaSchluessel() else { throw Kursquellenfehler.schluesselFehlt }
                return AlpacaLeser(symbole: symbole, schluessel: s)
            },
            verbinde: verbinde, warte: Kursquellen.schlafe, jetzt: { Date() })
    }
}
