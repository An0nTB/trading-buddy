import Foundation
import Testing
@testable import TradingCore

/// Kern-Befunde aus dem dritten Gegencheck (Doc 49: G1, G5, G8; G4 und G7 bringt AP12 in #177). Sollwerte von Hand (02.10.2026).
private let gUTC = TimeZone(secondsFromGMT: 0)!

private func gZeit(_ iso: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = gUTC
    return formatter.date(from: iso)!
}

/// Vier ETH/BTC-Trades an einem Tag, je 5 BTC Verlust: Für BTC gibt es keinen EZB-Kurs.
private let btcTrades = (0..<4).map { i in
    Trade(id: "b\(i)", symbol: "ETHBTC", side: .buy, lots: 1, openTime: gZeit("2026-03-02T1\(i):00:00Z"),
          closeTime: gZeit("2026-03-02T1\(i):30:00Z"), openPrice: 1, closePrice: 1, profit: -5, waehrung: "BTC")
}

@Test func g1RegelnZaehlenTradesOhneKurs() throws {
    let angleich = Waehrungsangleich(btcTrades, kontowaehrung: "EUR", kurse: nil)
    #expect(angleich.trades.isEmpty)
    #expect(angleich.ohneKursIDs == ["b0", "b1", "b2", "b3"])
    // Anzahl zählt, Betrag nicht: Der BTC-Verlust ist kein Euro-Tagesverlust.
    let regeln = Handelsregeln(maxTagesverlust: 1, maxTradesJeTag: 3, maxRisikoJeTrade: 1)
    let verstoesse = Regelpruefung.pruefe(angleich, regeln: regeln, zeitzone: gUTC)
    #expect(verstoesse.map(\.trade) == ["b3"])
    #expect(verstoesse.map(\.art) == [.tradesJeTag])
    let staende = Regelpruefung.tagesstaende(angleich, regeln: regeln, zeitzone: gUTC)
    #expect(staende.map(\.trades) == [4])
    #expect(staende.map(\.netto) == [0])
    #expect(staende.map(\.verstoesse) == [1])

    let maerz = try #require(Zeitspanne.monat(jahr: 2026, monat: 3, zeitzone: gUTC))
    let bericht = Zeitraumbericht(trades: btcTrades, zeitraum: maerz, zeitzone: gUTC, kontowaehrung: "EUR",
                                  regeln: regeln)
    #expect(bericht.regelverstoesse.map(\.trade) == ["b3"])
    #expect(bericht.ohneKurs == 4)
}

@Test func g5USDTAufDollarkontoOhneKurse() {
    let usdt = Trade(id: "t", symbol: "BTCUSDT", side: .buy, lots: 1, openTime: gZeit("2026-03-02T10:00:00Z"),
                     closeTime: gZeit("2026-03-02T11:00:00Z"), openPrice: 1, closePrice: 1, profit: 42,
                     waehrung: "USDT")
    let angleich = Waehrungsangleich([usdt], kontowaehrung: "USD", kurse: nil)
    #expect(angleich.ohneKurs.isEmpty)
    #expect(angleich.trades.map(\.profit) == [42])
}

@Test func g8FreieTageSindKeinMonat() throws {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let spanne = try #require(Zeitspanne.tage(von: DateComponents(year: 2025, month: 2, day: 28),
                                              bis: DateComponents(year: 2025, month: 3, day: 27), zeitzone: berlin))
    let vor = spanne.vorzeitraum(zeitzone: berlin)
    var k = Calendar(identifier: .gregorian)
    k.timeZone = berlin
    #expect(vor.bis == spanne.von)
    #expect(k.dateComponents([.day], from: vor.von, to: vor.bis).day == 28)
}
