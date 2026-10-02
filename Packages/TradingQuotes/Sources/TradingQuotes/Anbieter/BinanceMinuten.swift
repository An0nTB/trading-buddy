import Foundation
import TradingCore

/// Minutenkerzen von Binance Spot, ohne Schlüssel. Format laut developers.binance.com („Kline/Candlestick data“,
/// REST), gelesen 02.10.2026: GET /api/v3/klines mit `symbol`, `interval=1m`, `startTime`, `endTime` (ms, UTC),
/// `limit` höchstens 1.000; Gewicht 2. Antwort je Kerze `[Beginn ms, "open", "high", "low", "close", "volume",
/// Ende ms, …]` (12 Felder). Für reine Marktdaten nennt die Doku den Zugang https://data-api.binance.vision
/// („General API Information“, gelesen 02.10.2026), wie bei den Echtzeitkursen.
struct BinanceMinuten: Minutenquelle {
    let id = "binance"
    let abruf: Abruf
    static let jeAbruf = 1_000
    /// 31 Tage sind 44.640 Minuten, also 45 Abrufe; mehr lässt `Minutenlader.hoechstdauer` nicht zu.
    static let hoechstseiten = 46

    static func anfrage(_ symbol: String, von: Date, bis: Date) -> Abrufanfrage {
        var teile = URLComponents(string: "https://data-api.binance.vision/api/v3/klines")!
        teile.queryItems = [URLQueryItem(name: "symbol", value: symbol.uppercased()),
                            URLQueryItem(name: "interval", value: "1m"),
                            URLQueryItem(name: "startTime", value: String(ms(von))),
                            // endTime schließt ein; eine Millisekunde früher hält das Fenster halboffen.
                            URLQueryItem(name: "endTime", value: String(ms(bis) - 1)),
                            URLQueryItem(name: "limit", value: String(jeAbruf))]
        return Abrufanfrage(url: teile.url!)
    }

    static func ms(_ datum: Date) -> Int64 { Int64((datum.timeIntervalSince1970 * 1000).rounded()) }

    /// Eine Zeile: Zahlen und Texte gemischt, nur die ersten fünf Felder zählen.
    private struct Zeile: Decodable {
        let beginn: Int64
        let open, high, low, close: Zahl

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            beginn = try c.decode(Int64.self)
            open = try c.decode(Zahl.self)
            high = try c.decode(Zahl.self)
            low = try c.decode(Zahl.self)
            close = try c.decode(Zahl.self)
        }
    }

    private struct Fehler: Decodable {
        let code: Int?
        let msg: String?
    }

    static func lies(_ daten: Data) throws -> [Zeitkerze] {
        guard let zeilen = try? JSONDecoder().decode([Zeile].self, from: daten) else { throw Verlaufsfehler.format }
        return zeilen.map {
            Zeitkerze(beginn: Zeitstempel.ausMillisekunden($0.beginn), dauer: 60, open: $0.open.wert,
                      high: $0.high.wert, low: $0.low.wert, close: $0.close.wert)
        }
    }

    func minutenkerzen(_ quellSymbol: String, von: Date, bis: Date) async throws -> [Zeitkerze] {
        var alle: [Zeitkerze] = []
        var start = von
        for _ in 0..<Self.hoechstseiten where start < bis {
            let antwort = try await abruf(Self.anfrage(quellSymbol, von: start, bis: bis))
            guard antwort.status == 200 else {
                let text = (try? JSONDecoder().decode(Fehler.self, from: antwort.daten))?.msg
                throw text.map { Verlaufsfehler.anbieter("Binance \(antwort.status): \($0)") }
                    ?? Verlaufsfehler.http(antwort.status)
            }
            let kerzen = try Self.lies(antwort.daten)
            alle += kerzen
            guard kerzen.count >= Self.jeAbruf, let letzte = kerzen.last else { break }
            start = letzte.ende
        }
        return alle.sorted { $0.beginn < $1.beginn }
    }
}
