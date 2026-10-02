import Foundation

/// Tageskerzen von Kraken, ohne Schlüssel. Format laut docs.kraken.com (REST „Get OHLC Data“), gelesen 02.10.2026:
/// GET https://api.kraken.com/0/public/OHLC mit `pair`, `interval` (1440 = Tag), `since`; höchstens 720 Einträge.
/// `assetVersion=1` erlaubt Paarnamen wie „BTC/EUR“ (wie WebSocket v2). Antwort
/// `{"error":[],"result":{"<Paar>":[[zeit,"open","high","low","close","vwap","volume",anzahl],…],"last":…}}`.
struct KrakenVerlauf: Verlaufsquelle {
    let id = "kraken"
    let abruf: Abruf

    static func anfrage(_ paar: String, seit: Date) -> Abrufanfrage {
        var teile = URLComponents(string: "https://api.kraken.com/0/public/OHLC")!
        teile.queryItems = [URLQueryItem(name: "pair", value: paar),
                            URLQueryItem(name: "interval", value: "1440"),
                            URLQueryItem(name: "since", value: String(Int(seit.timeIntervalSince1970))),
                            URLQueryItem(name: "assetVersion", value: "1")]
        return Abrufanfrage(url: teile.url!)
    }

    private struct Antwort: Decodable {
        let error: [String]
        let result: [String: Eintraege]?
    }

    /// Unter `result` stehen das Paar (Liste) und `last` (Zahl); nur die Liste zählt.
    private enum Eintraege: Decodable {
        case kerzen([Zeile])
        case anderes

        init(from decoder: Decoder) throws {
            if let zeilen = try? decoder.singleValueContainer().decode([Zeile].self) {
                self = .kerzen(zeilen)
            } else {
                self = .anderes
            }
        }
    }

    /// `[zeit, open, high, low, close, vwap, volume, anzahl]`, Preise als Text.
    private struct Zeile: Decodable {
        let zeit: Int64
        let eroeffnung, hoch, tief, schluss: Zahl
        let volumen: Zahl

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            zeit = try c.decode(Int64.self)
            eroeffnung = try c.decode(Zahl.self)
            hoch = try c.decode(Zahl.self)
            tief = try c.decode(Zahl.self)
            schluss = try c.decode(Zahl.self)
            _ = try c.decode(Zahl.self)
            volumen = try c.decode(Zahl.self)
        }
    }

    static func lies(_ daten: Data, seit: Date, jetzt: Date) throws -> [Tageskerze] {
        guard let antwort = try? JSONDecoder().decode(Antwort.self, from: daten) else { throw Verlaufsfehler.format }
        if let fehler = antwort.error.first { throw Verlaufsfehler.anbieter("Kraken: \(fehler)") }
        var zeilen: [Zeile] = []
        for case .kerzen(let liste) in (antwort.result ?? [:]).values { zeilen += liste }
        return zeilen.map { z in
            let zeit = Date(timeIntervalSince1970: TimeInterval(z.zeit))
            return Tageskerze(zeit: zeit, eroeffnung: z.eroeffnung.wert, hoch: z.hoch.wert, tief: z.tief.wert,
                              schluss: z.schluss.wert, volumen: z.volumen.wert,
                              abgeschlossen: Tageskerze.istAbgeschlossen(zeit, jetzt: jetzt))
        }
        .filter { $0.zeit >= seit }
        .sorted { $0.zeit < $1.zeit }
    }

    func tageskerzen(_ quellSymbol: String, seit: Date, jetzt: Date) async throws -> [Tageskerze] {
        let antwort = try await abruf(Self.anfrage(quellSymbol, seit: seit))
        // Kraken meldet Fehler meist mit Status 200 im Feld `error`; andere Status gelten als Abbruch.
        guard antwort.status == 200 else { throw Verlaufsfehler.http(antwort.status) }
        return try Self.lies(antwort.daten, seit: seit, jetzt: jetzt)
    }
}

extension Kursverlaeufe {
    /// Tageskerzen für Krypto-Paare wie „BTC/EUR“ von Kraken, ohne Schlüssel.
    public static func kraken(abruf: @escaping Abruf = Kursverlaeufe.urlSession) -> any Verlaufsquelle {
        KrakenVerlauf(abruf: abruf)
    }
}
