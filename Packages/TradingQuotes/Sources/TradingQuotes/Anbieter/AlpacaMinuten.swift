import Foundation
import TradingCore

/// Minutenkerzen von Alpaca für US-Aktien (Teilmarkt IEX, gratis), mit dem Schlüssel der Echtzeitkurse.
/// Format laut docs.alpaca.markets („Historical bars“), gelesen 02.10.2026: wie die Tageskerzen in
/// `AlpacaVerlauf`, mit `timeframe=1Min`, `start` und `end` nach RFC 3339, `limit` höchstens 10.000.
/// IEX liefert nur Minuten mit Umsatz an der IEX: Lücken außerhalb der Handelszeit und in ruhigen Minuten.
/// Die Einschränkung „latest 15 minutes“ des Gratiszugangs gilt für den Gesamtmarkt (SIP), nicht für IEX
/// (Doc 39, Prüfprotokoll).
struct AlpacaMinuten: Minutenquelle {
    let id = "alpaca"
    let schluessel: any AlpacaSchluesselquelle
    let abruf: Abruf
    /// Ein Monat Handelszeit hat rund 8.200 Minuten: Eine Seite reicht meist, fünf sind Schutz.
    static let hoechstseiten = 5

    static func anfrage(_ symbol: String, von: Date, bis: Date, seite: String?,
                        schluessel: AlpacaSchluessel) -> Abrufanfrage {
        let erlaubt = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let pfad = symbol.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? symbol
        var teile = URLComponents(string: "https://data.alpaca.markets/v2/stocks/\(pfad)/bars")!
        var felder = [URLQueryItem(name: "timeframe", value: "1Min"),
                      URLQueryItem(name: "start", value: zeit(von)),
                      URLQueryItem(name: "end", value: zeit(bis)),
                      URLQueryItem(name: "feed", value: "iex"),
                      // Ungesplittete Preise wie beim Trade: ein späterer Split verfälscht sonst MAE/MFE/R (Doc 59 B1).
                      URLQueryItem(name: "adjustment", value: "raw"),
                      URLQueryItem(name: "limit", value: "10000")]
        if let seite { felder.append(URLQueryItem(name: "page_token", value: seite)) }
        teile.queryItems = felder
        return Abrufanfrage(url: teile.url!, kopf: ["APCA-API-KEY-ID": schluessel.schluesselID,
                                                    "APCA-API-SECRET-KEY": schluessel.geheimnis])
    }

    /// „2027-01-14T14:30:00Z“.
    static func zeit(_ datum: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: datum)
    }

    static func lies(_ daten: Data, symbol: String) throws -> (kerzen: [Zeitkerze], weiter: String?) {
        guard let antwort = try? JSONDecoder().decode(AlpacaVerlauf.Antwort.self, from: daten) else {
            throw Verlaufsfehler.format
        }
        let roh: [AlpacaVerlauf.Kerze]
        switch antwort.bars {
        case .liste(let liste): roh = liste
        case .jeSymbol(let je): roh = je[symbol] ?? []
        case nil: roh = []
        }
        let kerzen = try roh.map { k in
            guard let beginn = Zeitstempel.lies(k.t) else { throw Verlaufsfehler.format }
            return Zeitkerze(beginn: beginn, dauer: 60, open: k.o.wert, high: k.h.wert, low: k.l.wert, close: k.c.wert)
        }
        return (kerzen, antwort.weiter.flatMap { $0.isEmpty ? nil : $0 })
    }

    func minutenkerzen(_ quellSymbol: String, von: Date, bis: Date) async throws -> [Zeitkerze] {
        guard let s = try await schluessel.alpacaSchluessel() else { throw Verlaufsfehler.schluesselFehlt }
        var alle: [Zeitkerze] = []
        var seite: String?
        for _ in 0..<Self.hoechstseiten {
            let antwort = try await abruf(Self.anfrage(quellSymbol, von: von, bis: bis, seite: seite, schluessel: s))
            guard antwort.status == 200 else {
                let text = (try? JSONDecoder().decode(AlpacaVerlauf.Fehler.self, from: antwort.daten))?.message
                throw text.map { Verlaufsfehler.anbieter("Alpaca \(antwort.status): \($0)") }
                    ?? Verlaufsfehler.http(antwort.status)
            }
            let gelesen = try Self.lies(antwort.daten, symbol: quellSymbol)
            alle += gelesen.kerzen
            guard let weiter = gelesen.weiter else { break }
            seite = weiter
        }
        return alle.sorted { $0.beginn < $1.beginn }
    }
}
