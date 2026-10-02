import Foundation
import Testing
@testable import TradingCore

/// Währungsangleich (Doc 40, W2): Beträge fremder Währung zum Referenzkurs in die Kontowährung.
/// Sollwerte von Hand: 1 EUR = 1,25 USD = 0,85 GBP am 02.03.2026.
private func angleichZeit(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

private func angleichTrade(_ id: String, _ zu: String, _ profit: Decimal, waehrung: String?,
                           kommission: Decimal = 0) -> Trade {
    Trade(id: id, symbol: "BTC", side: .buy, lots: 1, openTime: angleichZeit(zu).addingTimeInterval(-600),
          closeTime: angleichZeit(zu), openPrice: 100, closePrice: 110, commission: kommission, profit: profit,
          produktart: .krypto, waehrung: waehrung)
}

private let angleichTrades = [
    angleichTrade("eur", "2026-03-02T10:00:00Z", -80, waehrung: nil),
    angleichTrade("usd", "2026-03-02T12:00:00Z", 500, waehrung: "usd", kommission: -5),
    // 03.03. ohne Kurs: der Kurs vom Vortag gilt.
    angleichTrade("usdt", "2026-03-03T09:00:00Z", 125, waehrung: "USDT"),
    angleichTrade("gbp", "2026-03-02T13:00:00Z", 10, waehrung: "GBP"),
]

private let angleichKurse = Referenzkurse(kurse: [Journaltag("2026-03-02")!: ["USD": dezimal("1.25")]])

private func dezimal(_ text: String) -> Decimal { Decimal(string: text)! }

@Test func waehrungsangleichInEuro() {
    let a = Waehrungsangleich(angleichTrades, kontowaehrung: "eur", kurse: angleichKurse)
    #expect(a.trades.map(\.id) == ["eur", "usd", "usdt"])
    #expect(a.trades.map(\.profit) == [-80, 400, 100])
    #expect(a.trades[1].commission == -4 && a.trades[1].waehrung == nil && a.trades[1].netProfit == 396)
    // Kurse bleiben in Kurswährung, der Wert je Kurspunkt folgt dem umgerechneten Ergebnis.
    #expect(a.trades[1].openPrice == 100 && a.trades[1].closePrice == 110)
    #expect(a.umgerechnet == ["usd", "usdt"] && a.ohneKurs.map(\.id) == ["gbp"])
    #expect(a.fremdwaehrungen == ["GBP", "USD", "USDT"])

    let ohne = Waehrungsangleich(angleichTrades, kontowaehrung: "EUR", kurse: nil)
    #expect(ohne.trades.map(\.id) == ["eur"] && ohne.ohneKurs.count == 3 && ohne.umgerechnet.isEmpty)
}

@Test func waehrungsangleichInDollar() {
    // Ohne Angabe gilt die Kontowährung, deshalb hier EUR ausdrücklich.
    let trades = [angleichTrade("eur", "2026-03-02T10:00:00Z", -80, waehrung: "EUR"),
                  angleichTrade("usd", "2026-03-02T12:00:00Z", 500, waehrung: "USD")] + angleichTrades.suffix(2)
    let a = Waehrungsangleich(trades, kontowaehrung: "USD", kurse: angleichKurse)
    // EUR −80 × 1,25; USD bleibt; USDT gilt als USD.
    #expect(a.trades.map(\.profit) == [-100, 500, 125])
    #expect(a.umgerechnet == ["eur", "usdt"] && a.fremdwaehrungen == ["EUR", "GBP", "USDT"])
    let kurse = Referenzkurse(kurse: [Journaltag("2026-03-02")!: ["USD": dezimal("1.25"), "GBP": dezimal("0.85")]])
    #expect(kurse.umrechnen(100, von: "USD", nach: "GBP", am: angleichZeit("2026-03-02T12:00:00Z")) == 68)
    #expect(kurse.umrechnen(100, von: "usdt", nach: "USD", am: angleichZeit("2026-01-01T12:00:00Z")) == 100)
    #expect(kurse.umrechnen(100, von: "JPY", nach: "EUR", am: angleichZeit("2026-03-02T12:00:00Z")) == nil)
    #expect(kurse.inEuro(125, waehrung: "USD", am: angleichZeit("2026-03-02T12:00:00Z")) == 100)
}

@Test func monatsberichtRechnetFremdwaehrungUm() throws {
    let utc = TimeZone(secondsFromGMT: 0)!
    let trades = Array(angleichTrades.prefix(2))
    let mit = try #require(Monatsbericht(trades: trades, jahr: 2026, monat: 3, zeitzone: utc, kontowaehrung: "EUR",
                                         kurse: angleichKurse))
    // −80 EUR und +500 USD (400 EUR) abzüglich 4 EUR Kommission.
    #expect(mit.auswertung.kennzahlen.netto == 316)
    #expect(mit.umgerechnet == 1 && mit.ohneKurs == 0 && mit.fremdwaehrungen == ["USD"])
    #expect(mit.beste.first?.id == "usd" && mit.beste.first?.netProfit == 396)

    let ohne = try #require(Monatsbericht(trades: trades, jahr: 2026, monat: 3, zeitzone: utc, kontowaehrung: "EUR"))
    #expect(ohne.auswertung.kennzahlen.netto == -80)
    #expect(ohne.umgerechnet == 0 && ohne.ohneKurs == 1 && ohne.fremdwaehrungen == ["USD"])
}
