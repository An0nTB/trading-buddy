import Foundation

/// Tageskerzen von Alpaca (Teilmarkt IEX, gratis), mit dem Schlüssel der Echtzeitkurse.
/// Format laut docs.alpaca.markets („Historical bars“), gelesen 02.10.2026: GET
/// https://data.alpaca.markets/v2/stocks/{symbol}/bars mit `timeframe=1Day`, `start` (JJJJ-MM-TT), `feed=iex`,
/// `adjustment`, `limit` (höchstens 10.000), `page_token`; Kerzen mit `t`, `o`, `h`, `l`, `c`, `v`, dazu
/// `next_page_token`. Ob `bars` beim Einzelabruf eine Liste oder (wie beim Abruf mehrerer Symbole) ein Objekt je
/// Symbol ist, zeigt die Doku-Seite nicht vollständig; der Leser nimmt beides an. Schlüssel im Kopf
/// `APCA-API-KEY-ID` und `APCA-API-SECRET-KEY`.
struct AlpacaVerlauf: Verlaufsquelle {
    let id = "alpaca"
    let schluessel: any AlpacaSchluesselquelle
    let abruf: Abruf
    /// Schutz gegen Endlosschleifen bei fehlerhaftem `next_page_token`; ein Jahr Tageskerzen passt in eine Seite.
    static let hoechstseiten = 5

    static func anfrage(_ symbol: String, seit: Date, seite: String?, schluessel: AlpacaSchluessel) -> Abrufanfrage {
        let erlaubt = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let pfad = symbol.addingPercentEncoding(withAllowedCharacters: erlaubt) ?? symbol
        var teile = URLComponents(string: "https://data.alpaca.markets/v2/stocks/\(pfad)/bars")!
        var felder = [URLQueryItem(name: "timeframe", value: "1Day"),
                      URLQueryItem(name: "start", value: tag(seit)),
                      URLQueryItem(name: "feed", value: "iex"),
                      // Splits herausgerechnet, sonst erscheint ein Split als Kurssturz.
                      URLQueryItem(name: "adjustment", value: "split"),
                      URLQueryItem(name: "limit", value: "10000")]
        if let seite { felder.append(URLQueryItem(name: "page_token", value: seite)) }
        teile.queryItems = felder
        return Abrufanfrage(url: teile.url!, kopf: ["APCA-API-KEY-ID": schluessel.schluesselID,
                                                    "APCA-API-SECRET-KEY": schluessel.geheimnis])
    }

    static func tag(_ datum: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: datum)
    }

    struct Kerze: Decodable {
        let t: String
        let o, h, l, c: Zahl
        let v: Zahl?
    }

    enum Kerzen: Decodable {
        case liste([Kerze])
        case jeSymbol([String: [Kerze]])

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let liste = try? c.decode([Kerze].self) {
                self = .liste(liste)
            } else {
                self = .jeSymbol(try c.decode([String: [Kerze]].self))
            }
        }
    }

    struct Antwort: Decodable {
        let bars: Kerzen?
        let weiter: String?

        private enum CodingKeys: String, CodingKey {
            case bars
            case weiter = "next_page_token"
        }
    }

    struct Fehler: Decodable {
        let message: String?
    }

    static func lies(_ daten: Data, symbol: String, jetzt: Date) throws -> (kerzen: [Tageskerze], weiter: String?) {
        guard let antwort = try? JSONDecoder().decode(Antwort.self, from: daten) else { throw Verlaufsfehler.format }
        let roh: [Kerze]
        switch antwort.bars {
        case .liste(let liste): roh = liste
        case .jeSymbol(let je): roh = je[symbol] ?? []
        case nil: roh = []
        }
        let kerzen = try roh.map { k in
            guard let zeit = Zeitstempel.lies(k.t) else { throw Verlaufsfehler.format }
            return Tageskerze(zeit: zeit, eroeffnung: k.o.wert, hoch: k.h.wert, tief: k.l.wert, schluss: k.c.wert,
                              volumen: k.v?.wert, abgeschlossen: Tageskerze.istAbgeschlossen(zeit, jetzt: jetzt))
        }
        let weiter = antwort.weiter.flatMap { $0.isEmpty ? nil : $0 }
        return (kerzen, weiter)
    }

    func tageskerzen(_ quellSymbol: String, seit: Date, jetzt: Date) async throws -> [Tageskerze] {
        guard let s = try await schluessel.alpacaSchluessel() else { throw Verlaufsfehler.schluesselFehlt }
        var alle: [Tageskerze] = []
        var seite: String?
        for _ in 0..<Self.hoechstseiten {
            let antwort = try await abruf(Self.anfrage(quellSymbol, seit: seit, seite: seite, schluessel: s))
            guard antwort.status == 200 else {
                let text = (try? JSONDecoder().decode(Fehler.self, from: antwort.daten))?.message
                throw text.map { Verlaufsfehler.anbieter("Alpaca \(antwort.status): \($0)") }
                    ?? Verlaufsfehler.http(antwort.status)
            }
            let gelesen = try Self.lies(antwort.daten, symbol: quellSymbol, jetzt: jetzt)
            alle += gelesen.kerzen
            guard let weiter = gelesen.weiter else { break }
            seite = weiter
        }
        return alle.sorted { $0.zeit < $1.zeit }
    }
}

extension Kursverlaeufe {
    /// Tageskerzen für US-Aktien wie „AAPL“ von Alpaca (IEX). Ohne Schlüssel endet der Abruf mit `.schluesselFehlt`.
    public static func alpaca(schluessel: any AlpacaSchluesselquelle,
                              abruf: @escaping Abruf = Kursverlaeufe.urlSession) -> any Verlaufsquelle {
        AlpacaVerlauf(schluessel: schluessel, abruf: abruf)
    }
}
