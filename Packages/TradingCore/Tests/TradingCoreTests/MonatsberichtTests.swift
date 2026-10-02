import Foundation
import Testing
@testable import TradingCore

/// Monatsbericht März 2026 in Berlin. Sollwerte von Hand (02.10.2026):
/// März-Trades B, C, D, F netto −50, −60, +30, +200 = +120; Februar A −100; E schließt im April.
/// D öffnet nach −110 am selben Tag: Tagesverlust (Grenze 100).
private func berichtZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func berichtTrade(_ id: String, _ auf: String, _ zu: String, _ netto: Decimal) -> Trade {
    Trade(id: id, symbol: "DE40", side: .buy, lots: 1, openTime: berichtZeit(auf), closeTime: berichtZeit(zu),
          openPrice: 100, closePrice: 100, profit: netto)
}

private let berichtTrades = [
    berichtTrade("A", "2026-02-27T10:00:00Z", "2026-02-27T11:00:00Z", -100),
    berichtTrade("B", "2026-03-02T09:00:00Z", "2026-03-02T09:30:00Z", -50),
    berichtTrade("C", "2026-03-02T09:40:00Z", "2026-03-02T10:00:00Z", -60),
    berichtTrade("D", "2026-03-02T10:10:00Z", "2026-03-02T10:30:00Z", 30),
    berichtTrade("E", "2026-03-10T09:00:00Z", "2026-04-02T09:00:00Z", 20),
    berichtTrade("F", "2026-03-20T12:00:00Z", "2026-03-20T13:00:00Z", 200),
]

@Test func monatsberichtMaerz() throws {
    let berlin = TimeZone(identifier: "Europe/Berlin")!
    let ziele = [
        Reviewziel(text: "Höchstens 2 Trades je Tag", von: berichtZeit("2026-02-28T23:00:00Z"),
                   bis: berichtZeit("2026-03-31T22:00:00Z")),
        Reviewziel(text: "Januar", von: berichtZeit("2026-01-01T00:00:00Z"), bis: berichtZeit("2026-02-01T00:00:00Z")),
        Reviewziel(text: "Monatswechsel", von: berichtZeit("2026-03-25T00:00:00Z"),
                   bis: berichtZeit("2026-04-08T00:00:00Z")),
    ]
    let verpasst = [
        VerpassterTrade(zeit: berichtZeit("2026-03-05T10:00:00Z"), symbol: "DE40", seite: .buy, grund: .zoegern),
        VerpassterTrade(zeit: berichtZeit("2026-04-05T10:00:00Z"), symbol: "DE40", seite: .buy, grund: .zuSpaet),
    ]
    let b = try #require(Monatsbericht(trades: berichtTrades, jahr: 2026, monat: 3, zeitzone: berlin,
                                       kontowaehrung: "EUR", regeln: Handelsregeln(maxTagesverlust: 100),
                                       ziele: ziele, verpasst: verpasst, topAnzahl: 1))
    #expect(b.auswertung.trades.map(\.id) == ["B", "C", "D", "F"])
    #expect(b.auswertung.kennzahlen.netto == 120)
    #expect(b.auswertung.kennzahlenVorzeitraum.netto == -100)
    #expect(b.regelverstoesse.map(\.trade) == ["D"])
    #expect(b.anzahl(.tagesverlust) == 1 && b.anzahl(.tradesJeTag) == 0)
    #expect(b.disziplin.regeltreu == 3 && b.disziplin.verletzt == 1 && b.propFirmVerstoesse.isEmpty)
    #expect(b.muster.isEmpty)
    #expect(b.ziele.map(\.text) == ["Höchstens 2 Trades je Tag", "Monatswechsel"])
    let topf = try #require(b.steuerBisMonatsende.first)
    #expect(b.steuerBisMonatsende.count == 1 && topf.topf == .nichtZugeordnet)
    #expect(topf.gewinne == 230 && topf.verluste == -210 && topf.anzahl == 5)
    #expect(b.planwirkung.tageOhnePlan == 2 && b.planwirkung.tageMitPlan == 0)
    #expect(b.verpasste.anzahl == 1)
    #expect(b.beste.map(\.id) == ["F"] && b.schlechteste.map(\.id) == ["C"])
    #expect(b.tradesOhneUhrzeit == 0)
}

@Test func monatsberichtUngueltigerMonat() {
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(Monatsbericht(trades: berichtTrades, jahr: 2026, monat: 13, zeitzone: utc, kontowaehrung: "EUR") == nil)
}
