import Foundation
import Testing
@testable import TradingCore

/// Wochenbericht KW 10/2026 (Mo 02.03. bis So 08.03.) in Berlin. Sollwerte von Hand (02.10.2026):
/// Woche: W2, W3, W4 am 02.03. netto −50, −60, +30 = −80; W5 am 04.03. +200; zusammen +120.
/// Vorwoche: W1 −100. W6 schließt in KW 11. W4 öffnet nach −110 am selben Tag: Tagesverlust (Grenze 100).
private func wocheZeit(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.date(from: iso)!
}

private func wocheTrade(_ id: String, _ auf: String, _ zu: String, _ netto: Decimal) -> Trade {
    Trade(id: id, symbol: "DE40", side: .buy, lots: 1, openTime: wocheZeit(auf), closeTime: wocheZeit(zu),
          openPrice: 100, closePrice: 100, profit: netto)
}

private let wocheTrades = [
    wocheTrade("W1", "2026-02-25T10:00:00Z", "2026-02-25T11:00:00Z", -100),
    wocheTrade("W2", "2026-03-02T09:00:00Z", "2026-03-02T09:30:00Z", -50),
    wocheTrade("W3", "2026-03-02T09:40:00Z", "2026-03-02T10:00:00Z", -60),
    wocheTrade("W4", "2026-03-02T10:10:00Z", "2026-03-02T10:30:00Z", 30),
    wocheTrade("W5", "2026-03-04T12:00:00Z", "2026-03-04T13:00:00Z", 200),
    wocheTrade("W6", "2026-03-06T09:00:00Z", "2026-03-10T09:00:00Z", 20),
]

private let wocheBerlin = TimeZone(identifier: "Europe/Berlin")!

@Test func zeitraumberichtWoche() throws {
    let woche = Zeitspanne.woche(mit: wocheZeit("2026-03-04T12:00:00Z"), zeitzone: wocheBerlin)
    #expect(woche.von == wocheZeit("2026-03-01T23:00:00Z") && woche.bis == wocheZeit("2026-03-08T23:00:00Z"))
    let b = Zeitraumbericht(trades: wocheTrades, zeitraum: woche, zeitzone: wocheBerlin, kontowaehrung: "EUR",
                            regeln: Handelsregeln(maxTagesverlust: 100), topAnzahl: 1)
    #expect(b.zeitraum == woche)
    #expect(b.auswertung.trades.map(\.id) == ["W2", "W3", "W4", "W5"])
    #expect(b.auswertung.kennzahlen.netto == 120)
    // Vergleich mit der Vorwoche (gleich viele Tage davor).
    #expect(b.auswertung.vorzeitraum.von == wocheZeit("2026-02-22T23:00:00Z"))
    #expect(b.auswertung.kennzahlenVorzeitraum.netto == -100)
    let tage = b.tage.map { "\($0.tag) \($0.anzahl) \($0.netto)" }
    #expect(tage == ["2026-03-02 3 -80", "2026-03-04 1 200"])
    #expect(b.regelverstoesse.map(\.trade) == ["W4"] && b.anzahl(.tagesverlust) == 1)
    #expect(b.steuerjahr == 2026)
    let topf = try #require(b.steuerBisEnde.first)
    #expect(topf.gewinne == 230 && topf.verluste == -210 && topf.anzahl == 5)
    #expect(b.beste.map(\.id) == ["W5"] && b.schlechteste.map(\.id) == ["W3"])
    #expect(b.umgerechnet == 0 && b.ohneKurs == 0 && b.tradesOhneUhrzeit == 0)
    let kw = woche.kalenderwoche(zeitzone: wocheBerlin)
    #expect(kw?.jahr == 2026 && kw?.woche == 10)
}

@Test func zeitraumberichtMonatGleichMonatsbericht() throws {
    let monat = try #require(Monatsbericht(trades: wocheTrades, jahr: 2026, monat: 3, zeitzone: wocheBerlin,
                                           kontowaehrung: "EUR"))
    let spanne = try #require(Zeitspanne.monat(jahr: 2026, monat: 3, zeitzone: wocheBerlin))
    let b = Zeitraumbericht(trades: wocheTrades, zeitraum: spanne, zeitzone: wocheBerlin, kontowaehrung: "EUR")
    #expect(monat.bericht.zeitraum == spanne)
    #expect(monat.auswertung.trades.map(\.id) == b.auswertung.trades.map(\.id))
    // Im Monat zählt auch W6 (schließt am 10.03.): −80 + 200 + 20.
    #expect(monat.auswertung.kennzahlen.netto == 140 && b.auswertung.kennzahlen.netto == 140)
    #expect(monat.steuerBisMonatsende == b.steuerBisEnde)
    #expect(spanne.kalenderwoche(zeitzone: wocheBerlin) == nil)
}

@Test func kalenderwocheNachISO() throws {
    // KW 1/2026 beginnt am Montag 29.12.2025 (1. Januar 2026 ist ein Donnerstag).
    let eins = try #require(Zeitspanne.kalenderwoche(jahr: 2026, woche: 1, zeitzone: wocheBerlin))
    #expect(eins.von == wocheZeit("2025-12-28T23:00:00Z") && eins.bis == wocheZeit("2026-01-04T23:00:00Z"))
    let b = Zeitraumbericht(trades: [], zeitraum: eins, zeitzone: wocheBerlin, kontowaehrung: "EUR")
    #expect(b.steuerjahr == 2026 && b.tage.isEmpty)
    // 2026 hat 53 Wochen, 2025 nur 52.
    let dreiundfuenfzig = try #require(Zeitspanne.kalenderwoche(jahr: 2026, woche: 53, zeitzone: wocheBerlin))
    #expect(dreiundfuenfzig.von == wocheZeit("2026-12-27T23:00:00Z"))
    #expect(Zeitspanne.kalenderwoche(jahr: 2025, woche: 53, zeitzone: wocheBerlin) == nil)
    #expect(Zeitspanne.kalenderwoche(jahr: 2026, woche: 0, zeitzone: wocheBerlin) == nil)
    let zehn = Zeitspanne.kalenderwoche(jahr: 2026, woche: 10, zeitzone: wocheBerlin)
    #expect(zehn == Zeitspanne.woche(mit: wocheZeit("2026-03-08T12:00:00Z"), zeitzone: wocheBerlin))
}
